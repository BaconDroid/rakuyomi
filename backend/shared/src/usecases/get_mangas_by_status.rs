use anyhow::Result;

use crate::{
    database::Database,
    model::Manga,
    settings::LibrarySortingMode,
    source_collection::SourceCollection,
};

pub async fn get_mangas_by_status(
    db: &Database,
    status_ids: &[i64],
    source_collection: &impl SourceCollection,
    library_sorting_mode: &LibrarySortingMode,
) -> Result<Vec<Manga>> {
    db.get_mangas_by_status(status_ids, source_collection, library_sorting_mode)
        .await
}
