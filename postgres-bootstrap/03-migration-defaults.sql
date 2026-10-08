-- Fallback and repair path for the migration identity's default privileges.
--
-- 02-database-grants.sql normally declares these defaults while connected as the configured
-- Entra administrator. Azure PostgreSQL gives that administrator an Azure-managed administrative
-- relationship to Entra-created workload roles, so no bootstrap-created GRANT/REVOKE membership
-- is required.
--
-- If ALTER DEFAULT PRIVILEGES in 02 is ever refused by the platform, run this file as the
-- migration identity itself. A role can always set its own default privileges, so these
-- statements intentionally omit FOR ROLE and apply to the current role.
--
-- Example:
--
--   psql "host=psql-cronus-nonprod.postgres.database.azure.com port=5432 \
--         dbname=cronus_dev_ordering user=id-ordering-migrations-dev sslmode=require" \
--     -v runtime_role=id-ordering-dev -f 03-migration-defaults.sql
--
-- The four names in that example are nonprod's. For another environment, take them from its
-- model in models/<environment>.sh, which holds the same server, database and pair of
-- identities that bootstrap.sh works from.
--
-- This is also the repair path for existing objects. Default privileges affect only objects
-- created after they are declared, so the ON ALL TABLES / ON ALL SEQUENCES grants below catch up
-- any existing objects the runtime identity cannot yet use.
--
-- The runtime role still receives no CREATE privilege, ownership, or role membership.
--
-- Safe to run again.

\set ON_ERROR_STOP on

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"runtime_role";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO :"runtime_role";

-- Objects that already exist. A no-op on an empty schema, which is the state the bootstrap
-- normally runs in.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"runtime_role";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"runtime_role";
