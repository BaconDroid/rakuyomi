use anyhow::Context;
use serde::{Deserialize, Serialize};

use crate::tls::client_builder;

fn is_loopback_host(host: &str) -> bool {
    let host = host.trim_start_matches('[').trim_end_matches(']');
    let host = host.strip_suffix('.').unwrap_or(host);
    host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .map(|ip| ip.is_loopback())
            .unwrap_or(false)
}

fn is_allowed_bridge_url(url: &reqwest::Url) -> bool {
    url.scheme() == "https" || is_loopback_host(url.host_str().unwrap_or_default())
}

/// Rejects cleartext bridge URLs unless the host is loopback.
fn bridge_base_url(server_url: &str) -> anyhow::Result<reqwest::Url> {
    let url = reqwest::Url::parse(server_url)
        .with_context(|| format!("invalid OAuth bridge URL: {server_url}"))?;
    if !is_allowed_bridge_url(&url) {
        anyhow::bail!("OAuth bridge URL must use https (http is only allowed on loopback)");
    }
    Ok(url)
}

fn bridge_endpoint(base: &reqwest::Url, path: &str) -> reqwest::Url {
    let mut url = base.clone();
    let base_path = url.path().trim_end_matches('/');
    url.set_path(&format!("{base_path}/{path}"));
    url
}

fn validate_session_id(session_id: &str) -> anyhow::Result<()> {
    let valid = !session_id.is_empty()
        && session_id.len() <= 64
        && session_id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_');
    if !valid {
        anyhow::bail!("invalid OAuth session ID");
    }
    Ok(())
}

fn bridge_redirect_policy() -> reqwest::redirect::Policy {
    reqwest::redirect::Policy::custom(|attempt| {
        if attempt.previous().len() >= 10 {
            return attempt.error("too many redirects");
        }
        if is_allowed_bridge_url(attempt.url()) {
            attempt.follow()
        } else {
            attempt.error("OAuth bridge redirect to a non-loopback http URL")
        }
    })
}

/// The OAuth service type sent to the bridge server.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OAuthService {
    Anilist,
    MyAnimeList,
    Shikimori,
    Bangumi,
    Mangabaka,
}

impl std::fmt::Display for OAuthService {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OAuthService::Anilist => write!(f, "anilist"),
            OAuthService::MyAnimeList => write!(f, "myanimelist"),
            OAuthService::Shikimori => write!(f, "shikimori"),
            OAuthService::Bangumi => write!(f, "bangumi"),
            OAuthService::Mangabaka => write!(f, "mangabaka"),
        }
    }
}

#[derive(Debug, Serialize)]
struct CreateSessionRequest {
    service: OAuthService,
    #[serde(skip_serializing_if = "Option::is_none")]
    chat_id: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    device_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateSessionResponse {
    pub session_id: String,
    pub bridge_path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionStatus {
    Pending,
    Completed,
    Error,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum PollSessionResponse {
    Pending {
        service: OAuthService,
    },
    Completed {
        service: OAuthService,
        tokens: Option<OAuthTokens>,
    },
    Error {
        service: OAuthService,
        message: String,
    },
}

#[derive(Debug, Deserialize, Serialize)]
pub struct OAuthTokens {
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    pub client_id: Option<String>,
}

/// Create an OAuth session on the bridge server.
///
/// Returns the session ID and the URL the user should open on their phone.
pub async fn start_oauth_session(
    server_url: &str,
    service: OAuthService,
    chat_id: Option<i64>,
    device_name: Option<String>,
) -> anyhow::Result<CreateSessionResponse> {
    let base = bridge_base_url(server_url)?;
    let url = bridge_endpoint(&base, "api/oauth/session");
    let body = CreateSessionRequest {
        service,
        chat_id,
        device_name,
    };

    let client = client_builder()
        .timeout(std::time::Duration::from_secs(15))
        .redirect(bridge_redirect_policy())
        .build()
        .context("failed to build HTTP client")?;

    let resp = client
        .post(url.clone())
        .header("content-type", "application/json")
        .body(serde_json::to_string(&body)?)
        .send()
        .await
        .with_context(|| format!("failed to create OAuth session at {url}"))?
        .error_for_status()
        .with_context(|| format!("OAuth session creation failed at {url}"))?;

    let data: CreateSessionResponse = resp
        .json()
        .await
        .with_context(|| "failed to parse OAuth session response")?;

    Ok(data)
}

/// Poll the OAuth session status on the bridge server.
pub async fn poll_oauth_status(
    server_url: &str,
    session_id: &str,
    api_token: Option<&str>,
) -> anyhow::Result<PollSessionResponse> {
    validate_session_id(session_id)?;
    let base = bridge_base_url(server_url)?;
    let url = bridge_endpoint(&base, &format!("api/oauth/status/{session_id}"));

    let mut client_builder = client_builder()
        .timeout(std::time::Duration::from_secs(10))
        .redirect(bridge_redirect_policy());
    if let Some(token) = api_token {
        client_builder =
            client_builder.default_headers(reqwest::header::HeaderMap::from_iter(vec![(
                reqwest::header::AUTHORIZATION,
                reqwest::header::HeaderValue::from_str(&format!("Bearer {token}"))
                    .context("invalid API token")?,
            )]));
    }
    let client = client_builder
        .build()
        .context("failed to build HTTP client")?;

    let resp = client
        // codeql[rust/cleartext-transmission]: bridge_base_url and the
        // redirect policy reject cleartext for every non-loopback host.
        .get(url.clone())
        .send()
        .await
        .with_context(|| format!("failed to poll OAuth status at {url}"))?
        .error_for_status()
        .with_context(|| format!("OAuth status poll failed at {url}"))?;

    let data: PollSessionResponse = resp
        .json()
        .await
        .with_context(|| "failed to parse OAuth status response")?;

    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::{bridge_base_url, bridge_endpoint, is_allowed_bridge_url, validate_session_id};

    #[test]
    fn accepts_https_and_loopback_http() {
        for url in [
            "https://bot.example.com/",
            "http://127.0.0.1:8787",
            "http://localhost:8787",
            "http://localhost.:8787",
            "http://[::1]:8787",
        ] {
            assert!(
                bridge_base_url(url).is_ok(),
                "expected {url} to be accepted"
            );
        }
    }

    #[test]
    fn rejects_cleartext_remote_http() {
        let err = bridge_base_url("http://bot.example.com/").unwrap_err();
        assert!(err.to_string().contains("must use https"));
    }

    #[test]
    fn allows_only_https_or_loopback_redirects() {
        for url in [
            "https://bot.example.com/",
            "http://127.0.0.1:8787",
            "http://localhost.:8787",
        ] {
            assert!(
                is_allowed_bridge_url(&reqwest::Url::parse(url).unwrap()),
                "expected {url} to be allowed"
            );
        }
        assert!(!is_allowed_bridge_url(
            &reqwest::Url::parse("http://bot.example.com/").unwrap()
        ));
    }

    #[test]
    fn builds_endpoints_before_query_and_fragment() {
        let base = reqwest::Url::parse("https://bot.example.com/base/?token=x#frag").unwrap();
        let url = bridge_endpoint(&base, "api/oauth/status/abc123");
        assert_eq!(
            url.as_str(),
            "https://bot.example.com/base/api/oauth/status/abc123?token=x#frag"
        );
    }

    #[test]
    fn validates_session_ids() {
        assert!(validate_session_id("a1b2c3d4").is_ok());
        assert!(validate_session_id("abc-DEF_123").is_ok());
        assert!(validate_session_id("").is_err());
        assert!(validate_session_id("../cookie/sync").is_err());
        assert!(validate_session_id("abc/def").is_err());
        assert!(validate_session_id(&"a".repeat(65)).is_err());
    }
}
