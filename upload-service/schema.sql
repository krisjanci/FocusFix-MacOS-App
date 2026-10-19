-- No recordings or clear-text enrollment credentials in this database.
CREATE TABLE IF NOT EXISTS participants (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  revoked INTEGER NOT NULL DEFAULT 0 CHECK (revoked IN (0, 1))
);

-- Reservations survive a crash between R2 storage and confirming the receipt.
-- Retain completed receipts when archiving/deleting R2 files to prevent reuploads.
CREATE TABLE IF NOT EXISTS uploads (
  participant_id TEXT NOT NULL REFERENCES participants(id),
  session_id TEXT NOT NULL,
  day TEXT NOT NULL,
  seconds INTEGER NOT NULL CHECK (seconds > 0 AND seconds <= 10800),
  bytes INTEGER NOT NULL CHECK (bytes > 0 AND bytes <= 26214400),
  sha256 TEXT NOT NULL,
  completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
  PRIMARY KEY (participant_id, session_id)
);
CREATE INDEX IF NOT EXISTS uploads_day ON uploads(participant_id, day);

CREATE TABLE IF NOT EXISTS attempts (
  participant_id TEXT NOT NULL REFERENCES participants(id),
  day TEXT NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY (participant_id, day)
);
