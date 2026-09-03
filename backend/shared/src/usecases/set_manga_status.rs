use anyhow::Result;

use crate::database::Database;

pub async fn set_manga_status(
    db: &Database,
    source_id: &str,
    manga_id: &str,
    status_id: i64,
) -> Result<()> {
    db.set_manga_status(source_id, manga_id, status_id).await
}
