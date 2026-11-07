use anyhow::Context;
use serde::{Deserialize, Serialize};

use crate::tls::client_builder;

/// Rejects cleartext bridge URLs unless the host is loopback.
fn bridge_base_url(server_url: &str) -> anyhow::Result<reqwest::Url> {
    let url = reqwest::Url::parse(server_url)
        .with_context(|| format!("invalid OAuth bridge URL: {server_url}"))?;
    let host = url
        .host_str()
        .unwrap_or_default()
        .trim_start_matches('[')
        .trim_end_matches(']');
    let loopback = host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .map(|ip| ip.is_loopback())
            .unwrap_or(false);
    if url.scheme() != "https" && !loopback {
        anyhow::bail!("OAuth bridge URL must use https (http is only allowed on loopback)");
    }
    Ok(url)
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
    let url = format!("{}/api/oauth/session", base.as_str().trim_end_matches('/'));
    let body = CreateSessionRequest {
        service,
        chat_id,
        device_name,
    };

    let client = client_builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .context("failed to build HTTP client")?;

    let resp = client
        .post(&url)
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
    let base = bridge_base_url(server_url)?;
    let url = format!(
        "{}/api/oauth/status/{}",
        base.as_str().trim_end_matches('/'),
        session_id
    );

    let mut client_builder = client_builder().timeout(std::time::Duration::from_secs(10));
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
        // codeql[rust/cleartext-transmission]: bridge_base_url rejects
        // cleartext for every non-loopback host.
        .get(&url)
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
    use super::bridge_base_url;

    #[test]
    fn accepts_https_and_loopback_http() {
        for url in [
            "https://bot.example.com/",
            "http://127.0.0.1:8787",
            "http://localhost:8787",
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
}
