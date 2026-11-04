use anyhow::Result;

use crate::{
    database::Database,
    model::{MangaId, TrackingCandidate},
};

pub async fn link_tracking_binding(
    db: &Database,
    manga_id: &MangaId,
    candidate: &TrackingCandidate,
) -> Result<()> {
    let previous_remote_id = db
        .list_tracking_bindings(manga_id)
        .await?
        .into_iter()
        .find(|binding| binding.service == candidate.service)
        .map(|binding| binding.remote_media_id);

    db.upsert_tracking_binding(manga_id, candidate).await?;

    // The stored sync state and dates belong to the entry that was linked
    // before; carrying them into a different remote entry would push the old
    // entry's reading dates to the new one.
    if previous_remote_id.is_some_and(|remote_id| remote_id != candidate.remote_media_id) {
        db.set_tracking_sync_state(manga_id, candidate.service, None, None, None, None)
            .await?;
    }

    Ok(())
}
