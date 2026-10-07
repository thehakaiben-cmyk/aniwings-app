-- Additive, repeatable migration for desktop email/password account metadata.
-- Identity and passwords remain managed by Firebase Authentication.
CREATE TABLE IF NOT EXISTS desktop_manual_users (
  uid TEXT PRIMARY KEY NOT NULL,
  email TEXT NOT NULL,
  username TEXT NOT NULL CHECK(length(username) BETWEEN 1 AND 30),
  email_verified INTEGER NOT NULL DEFAULT 0 CHECK(email_verified IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_login_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS desktop_manual_users_last_login ON desktop_manual_users(last_login_at);
