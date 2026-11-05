use anyhow::Result;

use crate::{database::Database, model::ReadingStatus};

pub async fn get_reading_statuses(db: &Database) -> Result<Vec<ReadingStatus>> {
    db.get_reading_statuses().await
}
