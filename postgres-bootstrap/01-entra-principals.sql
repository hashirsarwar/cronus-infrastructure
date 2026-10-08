-- The Entra identities that may sign in to this environment's Cronus databases.
--
-- Run against the postgres database, as the Entra administrator. The pgaadauth functions
-- exist only there, and the roles they create are cluster-wide, so this is the one place the
-- principals are made and every later statement can refer to them by name.
--
-- Nothing here grants access to anything. A principal is the right to sign in as a name;
-- what that name may reach is decided per database in 02-database-grants.sql.
--
-- The environment is not named in this file. Which identities belong to which databases
-- comes from models/<environment>.sh, through bootstrap.sh, so prod creates prod's
-- principals and nonprod creates nonprod's, and neither file mentions the other.
--
-- Terraform does not own this, deliberately. These are objects inside PostgreSQL, and the
-- Azure provider cannot read them: a role created here and a role created by a provider would
-- look identical on the next plan, so the provider would have to own the whole grant graph or
-- none of it. What Terraform does own is the managed identities these principals are mapped
-- to, which is why the object ids live in Azure and not in this file.
--
-- Object ids therefore arrive as a psql variable, as name=object-id pairs separated by
-- commas. An object id changes when an identity is deleted and recreated, and a stale one is
-- invisible until a workload fails to sign in, which is a hard failure to trace back to a
-- file. bootstrap.sh reads them from Azure and passes them in. By hand:
--
--   psql "$CONN" -f 01-entra-principals.sql \
--     -v principals="id-ordering-dev=$(az identity show -g rg-cronus-nonprod -n id-ordering-dev --query principalId -o tsv)"
--
-- Safe to run again. A principal that already exists is left alone, and one whose recorded
-- object id is no longer the identity it should name is reported rather than quietly kept.

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS pg_temp.expected_principal;

-- The role name is the managed identity's display name, so an identity is traceable from
-- Entra through this table to pg_stat_activity without an invented naming scheme in between.
-- The migration identities are the second half of each application environment: they are the
-- ones granted the right to change a schema, so they must not be the identity the
-- application's own pod runs as.
CREATE TEMP TABLE expected_principal (
  role_name text PRIMARY KEY,
  object_id text NOT NULL
);

-- Each entry is a role name and an object id joined by an equals sign. split_part takes the
-- part before it and the part after it, which is all the parsing this needs: neither a role
-- name nor an object id can contain an equals sign or a comma. The pairs are ordered by
-- bootstrap.sh, not here, so what arrives is the model rather than a sequence.
INSERT INTO expected_principal (role_name, object_id)
SELECT split_part(entry, '=', 1), split_part(entry, '=', 2)
FROM unnest(string_to_array(:'principals', ',')) AS entry
ORDER BY 1;

-- is_admin is false, and that is the point of the whole file: these identities get ordinary
-- roles, not membership of azure_pg_admin, so nothing an application runs can reach past its
-- own database or alter a schema. The Entra administrator is the only principal here with
-- server-wide reach, and it is a group because it administers rather than runs anything.
--
-- is_mfa is false because a workload identity has no interactive sign-in to challenge; asking
-- for an mfa claim would only refuse tokens that are perfectly good. It is a test of a claim,
-- not a switch that makes Entra issue one.
--
-- object_type 'service' is both managed identities and applications; the distinction Entra
-- draws between them does not exist here.
--
-- Creation is expressed as rows of SQL rather than as a procedural block so that what will be
-- executed is visible before it is: \gexec runs each row this query returns, and it returns a
-- row only for the principals that are missing.
SELECT format(
         'SELECT * FROM pgaadauth_create_principal_with_oid(%L, %L, %L, false, false);',
         e.role_name, e.object_id, 'service'
       )
FROM expected_principal e
WHERE NOT EXISTS (
        SELECT 1
        FROM pgaadauth_list_principals(false) p
        WHERE p.rolname = e.role_name
      )
ORDER BY e.role_name
\gexec

-- A role that exists but is now mapped to a different Entra object. Rows here mean an identity
-- was deleted and recreated: the role still exists, so the statement above left it alone, and
-- signing in as that identity will fail until this is dealt with. Nothing here repairs it
-- automatically, because dropping the role fails while it owns anything — see the README.
SELECT e.role_name,
       p.objectid AS mapped_to,
       e.object_id AS expected
FROM expected_principal e
JOIN pgaadauth_list_principals(false) p ON p.rolname = e.role_name
WHERE p.objectid <> e.object_id
ORDER BY e.role_name;

-- The state this file is meant to leave behind, for a human to read. Every row should say
-- service and isadmin = 0.
SELECT p.rolname,
       p.principaltype,
       p.isadmin
FROM pgaadauth_list_principals(false) p
JOIN expected_principal e ON e.role_name = p.rolname
ORDER BY p.rolname;
