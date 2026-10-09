-- Separate database for automated tests (see #32). The development database
-- (repohub_dev) is created from POSTGRES_DB.
CREATE DATABASE repohub_test OWNER repohub;
