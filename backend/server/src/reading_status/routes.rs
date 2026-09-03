use crate::model::{resolve_manga_covers, Manga};
use axum::extract::{Path, Query, State as StateExtractor};
use axum::routing::{delete, get, put};
use axum::{Json, Router};
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
        .route(
            "/mangas/{source_id}/{manga_id}/status",
            delete(remove_manga_status),
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

async fn remove_manga_status(
    StateExtractor(State { database, .. }): StateExtractor<State>,
    Path(params): Path<MangaPath>,
) -> Result<Json<()>, AppError> {
    usecases::remove_manga_status(&database, &params.source_id, &params.manga_id).await?;

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

    let mut mangas = usecases::get_mangas_by_status(
        &database,
        &query.status,
        &*source_manager.lock().await,
        library_sorting_mode,
    )
    .await?;

    if settings.library_view_mode != shared::settings::LibraryViewMode::Base {
        resolve_manga_covers(&mut mangas, &chapter_storage);
    }

    Ok(Json(
        mangas.into_iter().map(Manga::from).collect::<Vec<_>>(),
    ))
}
