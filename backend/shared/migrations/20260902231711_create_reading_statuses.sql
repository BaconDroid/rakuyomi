-- The seed order below IS the automation progression order: the
-- forward-only guard compares `status_id` numerically, so these ids must
-- never be renumbered. Clients persist them too (the Lua library filter
-- stores them in `rakuyomi_status_filter`), and
-- `manga_reading_status.status_id` references this table with no
-- `ON UPDATE CASCADE`.
--
-- The backfill and orphan purge live here so the feature ships as a
-- single migration: status is mandatory and defaults to Unread (id 1),
-- so older libraries are backfilled, and orphans left by earlier library
-- removals are purged.
--
-- INSERT OR IGNORE (not ON CONFLICT DO NOTHING): the upsert clause is
-- rejected on INSERT ... SELECT by some SQLite builds, while OR IGNORE
-- preserves existing assignments just the same.
CREATE TABLE reading_statuses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL
) STRICT;

CREATE TABLE manga_reading_status (
    source_id TEXT NOT NULL,
    manga_id TEXT NOT NULL,
    status_id INTEGER NOT NULL,
    PRIMARY KEY (source_id, manga_id),
    FOREIGN KEY (status_id) REFERENCES reading_statuses (id)
) STRICT;

-- Seed predefined statuses
INSERT INTO reading_statuses (id, name) VALUES (1, 'Unread');
INSERT INTO reading_statuses (id, name) VALUES (2, 'Reading');
INSERT INTO reading_statuses (id, name) VALUES (3, 'On Hold');
INSERT INTO reading_statuses (id, name) VALUES (4, 'Completed');
INSERT INTO reading_statuses (id, name) VALUES (5, 'Dropped');

INSERT OR IGNORE INTO manga_reading_status (source_id, manga_id, status_id)
SELECT source_id, manga_id, 1
FROM manga_library;

DELETE FROM manga_reading_status
WHERE NOT EXISTS (
    SELECT 1 FROM manga_library lib
    WHERE lib.source_id = manga_reading_status.source_id
    AND lib.manga_id = manga_reading_status.manga_id
);
