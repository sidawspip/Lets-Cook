-- Keep the stable provider/page identity separate from a short-lived resolved stream URL.
-- Existing queue rows used media_id for both, so preserve that behavior as a fallback.
ALTER TABLE room_watch_queue
    ADD COLUMN source_url VARCHAR(2000);

UPDATE room_watch_queue
SET source_url = media_id
WHERE source_url IS NULL
  AND (provider LIKE 'DIRECT_%'
       OR provider IN ('GOOGLE_DRIVE','DROPBOX','ONEDRIVE','BOX','NEXTCLOUD',
                       'INTERNET_ARCHIVE','X','TWITCH','VIMEO','NETFLIX',
                       'PRIME_VIDEO','CRUNCHYROLL'));
