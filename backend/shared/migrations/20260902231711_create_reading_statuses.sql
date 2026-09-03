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
INSERT INTO reading_statuses (id, name) VALUES (3, 'Completed');
INSERT INTO reading_statuses (id, name) VALUES (4, 'On Hold');
INSERT INTO reading_statuses (id, name) VALUES (5, 'Dropped');
