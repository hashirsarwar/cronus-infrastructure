-- What each identity may reach, in one database.
--
-- Run by bootstrap.sh once per database in the environment's model, connected to that
-- database, as the configured Entra administrator. It can also be run by hand for a single
-- database; see the README.
--
-- PostgreSQL roles are cluster-wide but databases are not. Each Cronus database therefore
-- removes the default PUBLIC access and grants CONNECT only to its runtime identity, its
-- migration identity, and the administrator group.
--
-- Every database gets the same five steps, all inside one transaction:
--
--   1. REVOKE ALL    -- remove PUBLIC database access, including CONNECT and TEMP.
--   2. GRANT CONNECT -- allow this database's runtime identity, migration identity, and admin.
--   3. REVOKE ALL    -- remove PUBLIC privileges from the public schema.
--   4. SCHEMA GRANTS -- runtime gets USAGE; migration gets USAGE + CREATE.
--   5. DEFAULTS      -- objects created later by the migration role grant DML to runtime.
--
-- One database per run is what makes the transaction the unit: a run either leaves a database
-- fully locked down or leaves it untouched, and never takes CONNECT off PUBLIC without having
-- granted it to the identities, which would shut everyone out. The database, the runtime
-- identity and the migration identity all arrive as psql variables, so the model of which
-- identity belongs to which database lives in models/<environment>.sh and nowhere else.
--
-- The ALTER DEFAULT PRIVILEGES statements target the migration role because that role will own
-- the objects created by EF migrations. On Azure PostgreSQL, Entra principals created through
-- pgaadauth are placed under the configured Entra administrator by Azure itself: the
-- administrator group appears in pg_auth_members with grantor azuresu and admin_option=true.
-- Therefore this bootstrap does not create or revoke role membership of its own; it relies on
-- Azure's administrator relationship to manage the non-admin workload roles.
--
-- Runtime identities receive no CREATE privilege and no ownership. Migration identities may
-- change schema objects, while runtime identities only receive the row/sequence privileges they
-- need after those objects exist.
--
-- Safe to run again: REVOKE, GRANT, and ALTER DEFAULT PRIVILEGES converge on the same state.

\set ON_ERROR_STOP on

BEGIN;

REVOKE ALL ON DATABASE :"database" FROM PUBLIC;

GRANT CONNECT ON DATABASE :"database"
  TO :"runtime_role",
     :"migration_role",
     :"admin_role";

REVOKE ALL ON SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO :"runtime_role";
GRANT USAGE, CREATE ON SCHEMA public TO :"migration_role";

ALTER DEFAULT PRIVILEGES FOR ROLE :"migration_role" IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"runtime_role";

ALTER DEFAULT PRIVILEGES FOR ROLE :"migration_role" IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO :"runtime_role";

COMMIT;

-- The result, for a human to read. Every privilege on this database, expanded rather than shown
-- as ACL text. aclexplode turns an ACL into one row per privilege, and acldefault supplies the
-- implicit ACL of a database nobody has granted on — which is the state that still admits
-- PUBLIC, so leaving it out here would hide the one case worth seeing.
--
-- A row whose grantee is PUBLIC is the failure this file exists to prevent. bootstrap.sh checks
-- the same thing across every database once the loop is finished, and that check is what gating
-- relies on; this listing is for reading.
SELECT coalesce(r.rolname, 'PUBLIC') AS grantee,
       a.privilege_type,
       a.is_grantable
FROM pg_database d
CROSS JOIN LATERAL aclexplode(coalesce(d.datacl, acldefault('d', d.datdba))) AS a
LEFT JOIN pg_roles r ON r.oid = a.grantee
WHERE d.datname = current_database()
ORDER BY grantee, a.privilege_type;
