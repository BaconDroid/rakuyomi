use anyhow::{Context, Result};

use crate::model::{SourceId, SourceInformation};
use crate::settings::{SourceList, SourceListType};
use crate::usecases::fetch_source_list::{expand_keiyoushi_ids, fetch_source_list};
use crate::usecases::resolve_source_list::{resolve_source_list, source_list_key};
use serde_json::Value;

/// Lists the sources published by every configured source list.
///
/// A source list that cannot be fetched or parsed (dead URL, HTML error page
/// instead of an index, malformed JSON) is skipped and logged instead of
/// failing the whole call: one broken list used to make the "available
/// sources" screen unusable for every other list the user had configured.
/// The call only fails when *no* list could be loaded, which keeps the
/// frontend's offline / reconnect handling (it retries on error) working
/// when there is simply no network.
pub async fn list_available_sources(
    source_lists: Vec<SourceList>,
) -> Result<Vec<SourceInformation>> {
    let mut source_informations: Vec<SourceInformation> = Vec::new();
    let mut failures: Vec<String> = Vec::new();

    for source_list in source_lists {
        match fetch_sources_of_list(&source_list).await {
            Ok(mut sources) => source_informations.append(&mut sources),
            Err(error) => {
                log::warn!(
                    "skipping unavailable source list {} ({:?}): {error:#}",
                    source_list.url,
                    source_list.source_type
                );
                failures.push(format!("{}: {error:#}", source_list.url));
            }
        }
    }

    if source_informations.is_empty() && !failures.is_empty() {
        anyhow::bail!(
            "failed to load every configured source list:\n{}",
            failures.join("\n")
        );
    }

    source_informations.sort_by_key(|source| source.name.clone());

    Ok(source_informations)
}

/// Fetches and normalises the sources published by a single source list.
async fn fetch_sources_of_list(source_list: &SourceList) -> Result<Vec<SourceInformation>> {
    let resolved_list = resolve_source_list(source_list).await;
    let key = source_list_key(source_list);

    let client = crate::tls::client_builder()
        .build()
        .with_context(|| "failed to create HTTP client".to_string())?;
    let value = fetch_source_list(&client, &resolved_list).await?;

    // Try both formats
    let mut sources = if value.is_array() {
        serde_json::from_value::<Vec<SourceInformation>>(normalize_ids(value))?
    } else if let Some(arr) = value.get("sources").and_then(|v| v.as_array()) {
        serde_json::from_value::<Vec<SourceInformation>>(normalize_ids(Value::Array(arr.clone())))?
    } else {
        anyhow::bail!(
            "unexpected JSON format for source list at {}: {}",
            resolved_list,
            value
        );
    };

    for src in &mut sources {
        src.source_of_source = Some(key.clone());
    }

    // Keiyoushi publishes one entry per bundled source language under the
    // same package id; multi-source extensions get `<pkg>:<lang>` ids so
    // entries match the sources installing them produces.
    if source_list.source_type == SourceListType::Keiyoushi {
        let mut entries = sources
            .iter()
            .map(|src| (src.id.value().to_string(), src.languages.first().cloned()))
            .collect::<Vec<_>>();
        expand_keiyoushi_ids(&mut entries);
        for (src, (id, _)) in sources.iter_mut().zip(entries) {
            src.id = SourceId::new(id);
        }
    }

    Ok(sources)
}

/// MangaYomi index entries publish numeric ids (`"id": 638504049`) and
/// keiyoushi index entries publish the extension package as `pkg`; the
/// shared `SourceInformation` model expects a string id, so both are
/// normalised here before deserialisation.
fn normalize_ids(value: Value) -> Value {
    let Value::Array(items) = value else {
        return value;
    };
    Value::Array(
        items
            .into_iter()
            .map(|item| {
                let Value::Object(mut map) = item else {
                    return item;
                };
                if let Some(Value::Number(n)) = map.get("id") {
                    if let Some(s) = n.as_i64().map(|n| n.to_string()) {
                        map.insert("id".to_string(), Value::String(s));
                    }
                } else if let Some(Value::String(pkg)) = map.get("pkg") {
                    map.insert("id".to_string(), Value::String(pkg.clone()));
                }
                Value::Object(map)
            })
            .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use url::Url;

    #[test]
    fn normalize_ids_stringifies_mangayomi_numeric_ids() {
        let value = serde_json::json!([
            {"id": 638504049, "name": "Madara Fixture", "lang": "en"},
            {"id": "royalroad", "name": "Royal Road"}
        ]);
        let normalized = normalize_ids(value);
        let items = normalized.as_array().unwrap();
        assert_eq!(items[0]["id"], serde_json::json!("638504049"));
        assert_eq!(items[1]["id"], serde_json::json!("royalroad"));
    }

    #[test]
    fn normalize_ids_uses_keiyoushi_pkg_as_id() {
        let value = serde_json::json!([
            {"name": "MangaPill", "pkg": "eu.kanade.tachiyomi.en.mangapill", "apk": "https://github.com/keiyoushi/extensions/releases/download/v1.4.x/tachiyomi-en.mangapill-v1.4.x.apk", "lang": "en", "code": 199, "version": "1.4.199", "hasReadme": true, "isNsfw": true},
            {"id": "en.aquamanga", "name": "Aqua Manga"}
        ]);
        let normalized = normalize_ids(value);
        let items = normalized.as_array().unwrap();
        assert_eq!(
            items[0]["id"],
            serde_json::json!("eu.kanade.tachiyomi.en.mangapill")
        );
        assert_eq!(items[0]["lang"], serde_json::json!("en"));
        assert_eq!(items[1]["id"], serde_json::json!("en.aquamanga"));
    }

    #[test]
    fn no_source_lists_is_not_an_error() {
        let sources = futures::executor::block_on(list_available_sources(Vec::new())).unwrap();
        assert!(sources.is_empty());
    }

    /// Serves `body` as the response to every request and returns the
    /// address to point a source list at.
    async fn serve_index(body: &'static str) -> std::net::SocketAddr {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            while let Ok((mut socket, _)) = listener.accept().await {
                tokio::spawn(async move {
                    let mut buf = [0u8; 2048];
                    let _ = socket.read(&mut buf).await;
                    let response = format!(
                        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
                        body.len(),
                        body
                    );
                    let _ = socket.write_all(response.as_bytes()).await;
                    let _ = socket.shutdown().await;
                });
            }
        });
        addr
    }

    fn aidoku_list(url: &str) -> SourceList {
        SourceList {
            url: Url::parse(url).unwrap(),
            source_type: SourceListType::Aidoku,
        }
    }

    /// A dead source list must not take the other lists down with it (issue
    /// #2: one 404ing index made the whole available-sources screen fail).
    #[tokio::test]
    async fn skips_broken_source_list_and_keeps_the_working_ones() {
        let addr = serve_index(
            r#"{"sources":[{"id":"en.working","name":"Working","version":1,"downloadURL":"sources/en.working-v1.aix","languages":["en"]}]}"#,
        )
        .await;

        let sources = list_available_sources(vec![
            // Connection refused: the list cannot be fetched at all.
            aidoku_list("http://127.0.0.1:1/index.min.json"),
            aidoku_list(&format!("http://{addr}/index.min.json")),
        ])
        .await
        .expect("a single broken list must not fail the listing");

        assert_eq!(sources.len(), 1);
        assert_eq!(sources[0].id.value(), "en.working");
    }

    /// HTML instead of an index (a host that 404s to a landing page) is a
    /// parse failure, skipped like any other broken list.
    #[tokio::test]
    async fn skips_source_list_serving_html() {
        let addr = serve_index("<!DOCTYPE html><html><body>404</body></html>").await;

        let error =
            list_available_sources(vec![aidoku_list(&format!("http://{addr}/index.min.json"))])
                .await
                .expect_err("every list failing is still an error");

        assert!(format!("{error:#}").contains("failed to load every configured source list"));
    }
}
