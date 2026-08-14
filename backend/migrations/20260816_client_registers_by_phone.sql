-- Clients do not have a name: the phone number is their identifier.
-- Backfill legacy placeholder/empty client display names to the client phone so
-- drivers and admins see the phone everywhere instead of 'User Name' or a stale
-- placeholder. Deleted accounts keep their neutral 'Удалённый пользователь' marker.
UPDATE users
SET full_name = phone
WHERE role = 'client'
  AND deleted_at IS NULL
  AND full_name IS DISTINCT FROM phone
  AND full_name <> 'Удалённый пользователь';