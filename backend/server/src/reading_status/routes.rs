use crate::model::{listing_response, Manga};
use axum::extract::{Path, State as StateExtractor};
use axum::routing::{get, put};
use axum::{Json, Router};
// axum's own `Query` uses `serde_urlencoded`, which rejects repeated keys
// (and a lone value) for a `Vec` field. `axum_extra`'s uses
// `serde_html_form`, which collects `?status=1&status=2` as expected.
use axum_extra::extract::Query;
use serde::Deserialize;
use shared::usecases;

use crate::state::State;
use crate::AppError;

pub fn routes() -> Router<State> {
    Router::new()
        .route("/reading-statuses", get(get_reading_statuses))
        .route(
            "/mangas/{source_id}/{manga_id}/status",
            put(set_manga_status),
        )
        .route("/mangas/by-status", get(get_mangas_by_status))
}

async fn get_reading_statuses(
    StateExtractor(State { database, .. }): StateExtractor<State>,
) -> Result<Json<Vec<shared::model::ReadingStatus>>, AppError> {
    let statuses = usecases::get_reading_statuses(&database).await?;

    Ok(Json(statuses))
}

#[derive(Deserialize)]
pub struct SetMangaStatusBody {
    pub status_id: i64,
}

#[derive(Deserialize)]
pub struct MangaPath {
    pub source_id: String,
    pub manga_id: String,
}

async fn set_manga_status(
    StateExtractor(State { database, .. }): StateExtractor<State>,
    Path(params): Path<MangaPath>,
    Json(body): Json<SetMangaStatusBody>,
) -> Result<Json<()>, AppError> {
    usecases::set_manga_status(
        &database,
        &params.source_id,
        &params.manga_id,
        body.status_id,
    )
    .await?;

    Ok(Json(()))
}

#[derive(Deserialize)]
pub struct GetMangasByStatusQuery {
    pub status: Vec<i64>,
}

async fn get_mangas_by_status(
    StateExtractor(State {
        database,
        source_manager,
        settings,
        chapter_storage,
        ..
    }): StateExtractor<State>,
    Query(query): Query<GetMangasByStatusQuery>,
) -> Result<Json<Vec<Manga>>, AppError> {
    let settings = settings.lock().await;

    let chapter_storage = chapter_storage.lock().await;
    let library_sorting_mode = &settings.library_sorting_mode;

    let mangas = usecases::get_mangas_by_status(
        &database,
        &query.status,
        &*source_manager.lock().await,
        library_sorting_mode,
    )
    .await?;

    Ok(listing_response(
        mangas,
        settings.library_view_mode,
        &chapter_storage,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The client sends `?status=1&status=2`, or a single `?status=3`.
    /// axum's own extractor rejects the repeated-key form for a `Vec`
    /// field, so this pins both query shapes.
    #[test]
    fn status_query_reads_single_and_repeated_keys() {
        let uri: axum::http::Uri = "/mangas/by-status?status=1&status=2".parse().unwrap();
        let Query(query) = Query::<GetMangasByStatusQuery>::try_from_uri(&uri).unwrap();
        assert_eq!(query.status, vec![1, 2]);

        let uri: axum::http::Uri = "/mangas/by-status?status=3".parse().unwrap();
        let Query(query) = Query::<GetMangasByStatusQuery>::try_from_uri(&uri).unwrap();
        assert_eq!(query.status, vec![3]);
    }
}
