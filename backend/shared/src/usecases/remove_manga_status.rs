use anyhow::Result;

use crate::database::Database;

pub async fn remove_manga_status(db: &Database, source_id: &str, manga_id: &str) -> Result<()> {
    db.remove_manga_status(source_id, manga_id).await
}
