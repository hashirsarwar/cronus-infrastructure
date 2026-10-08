#!/usr/bin/env bash
#
# Runs the PostgreSQL bootstrap for one Cronus environment against that environment's
# server: first the Entra principals, then what each of them may reach.
#
#   ./bootstrap.sh nonprod
#   ./bootstrap.sh prod
#
# What each environment contains is in models/<environment>.sh rather than in this script,
# so the script is the same for every environment and adding one means adding a file to
# that directory. The environment is required rather than defaulted: running the production
# bootstrap against the nonprod server because an argument was forgotten is the mistake
# this script should not be able to make.
#
# It has to run somewhere that can reach the server. Public network access is off and the
# server only exists inside its virtual network, so a machine outside it will fail to
# resolve <server>.postgres.database.azure.com. That is the design rather than a fault, and
# opening the server up to avoid it would undo the point of it. See the README for where
# this is meant to run from.
#
# The Entra token is the password and it lasts 5 to 60 minutes, so it is fetched here rather
# than handed in, and it is never written anywhere. You are the administrator: the server is
# administered by a group, and this authenticates as a member of it.
#
# Safe to run again. Both SQL files state facts rather than accumulate them.

# The server, the administrator group and the databases are read from the environment model
# below. shellcheck cannot follow that read, because the path is built from the argument, so
# it reports every one of them as a variable that was never assigned.
# shellcheck disable=SC2154

set -euo pipefail

# The Azure CLI image may not include the default `more` pager used by psql.
# Disable paging so bootstrap output is non-interactive and does not depend on pager packages.
export PSQL_PAGER=cat

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [ "$#" -ne 1 ]; then
  echo "usage: $(basename "$0") <environment>" >&2
  echo "       known environments: $(cd "$here/models" && ls ./*.sh 2>/dev/null | sed 's#^\./##; s#\.sh$##' | tr '\n' ' ')" >&2
  exit 2
fi

environment=$1
model="$here/models/${environment}.sh"

if [ ! -f "$model" ]; then
  echo "bootstrap: no model for '$environment' at $model" >&2
  exit 2
fi

# shellcheck source=/dev/null
. "$model"

if [ "${#databases[@]}" -eq 0 ]; then
  echo "bootstrap: $model declares no databases" >&2
  exit 2
fi

for tool in az psql; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "bootstrap: $tool is required and is not on PATH" >&2
    exit 1
  }
done

# The model, restated as the rows the checks below compare against: every database, the
# identity that serves traffic in it, and the identity that migrates it. The statements that
# create the principals and the grants are driven by the same three facts, so the two cannot
# disagree about which identity belongs to which database. That agreement is the boundary
# between the two applications, and it would fail silently if it were written down twice.
identities=()
workload_roles=()
workload_connect=()
expected_database=()
expected_connect=()
for row in "${databases[@]}"; do
  IFS=: read -r database runtime migration <<<"$row"

  identities+=("$runtime" "$migration")

  # The workload roles and the database each of them belongs to. The effective-access check
  # below enumerates every pairing of the one with the other and asserts this diagonal.
  workload_roles+=("('${runtime}')" "('${migration}')")
  workload_connect+=("('${database}', '${runtime}')" "('${database}', '${migration}')")

  expected_database+=("('${database}')")
  # The administrator group too, or the bootstrap would take away its own way back in — which
  # is exactly the accident the per-database transaction in 02-database-grants.sql also
  # guards against.
  expected_connect+=("('${database}', '${runtime}')" \
                     "('${database}', '${migration}')" \
                     "('${database}', '${admin_role}')")
done

expected_database_rows=$(IFS=,; echo "${expected_database[*]}")
expected_connect_rows=$(IFS=,; echo "${expected_connect[*]}")
workload_role_rows=$(IFS=,; echo "${workload_roles[*]}")
workload_connect_rows=$(IFS=,; echo "${workload_connect[*]}")

# Keep the token out of connection URIs and command-line arguments, which expose it to process listings.
PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv) || {
  echo "bootstrap: could not get an Entra token; is az logged in?" >&2
  exit 1
}
export PGPASSWORD

connection="host=${server}.postgres.database.azure.com port=5432 dbname=postgres user=${admin_role} sslmode=require"

echo "==> ${environment}: ${server} in ${resource_group}"

echo "==> Reading identity object ids from Azure"
principals=()
expected=()
for identity in "${identities[@]}"; do
  oid=$(az identity show --resource-group "$resource_group" --name "$identity" --query principalId -o tsv)
  [ -n "$oid" ] || {
    echo "bootstrap: $identity has no principal id" >&2
    exit 1
  }

  # The name and the object id together, as one psql variable that 01-entra-principals.sql
  # splits. They travel as a pair because the object id has to arrive beside the role it
  # belongs to: passing two lists would make a reordering of one of them a silent
  # authentication failure rather than an error.
  principals+=("${identity}=${oid}")
  # The same pair again, as a SQL row, for the drift check below.
  expected+=("('${identity}', '${oid}')")

  printf '    %-34s %s\n' "$identity" "$oid"
done

principals_arg=$(IFS=,; echo "${principals[*]}")
expected_rows=$(IFS=,; echo "${expected[*]}")

echo "==> Entra principals"
psql "$connection" -v principals="$principals_arg" -f "$here/01-entra-principals.sql"

echo "==> Database access"
# One database per run, connected to that database, so the transaction inside the file is the
# unit: a database is either fully locked down or untouched.
for row in "${databases[@]}"; do
  IFS=: read -r database runtime migration <<<"$row"

  printf '    %s\n' "$database"
  psql "host=${server}.postgres.database.azure.com port=5432 dbname=${database} user=${admin_role} sslmode=require" \
    -v database="$database" \
    -v runtime_role="$runtime" \
    -v migration_role="$migration" \
    -v admin_role="$admin_role" \
    -f "$here/02-database-grants.sql"
done

echo "==> Verifying"

# A role whose recorded object id is not the identity it names still exists, so 01 left it
# alone, and the only symptom is that the workload cannot sign in. Checked here because that
# failure appears in a pod's logs days later, a long way from this script.
drifted=$(psql "$connection" -tAc "
  SELECT count(*)
  FROM (VALUES ${expected_rows}) AS e (role_name, object_id)
  JOIN pgaadauth_list_principals(false) p ON p.rolname = e.role_name
  WHERE p.objectid <> e.object_id;
")

if [ "$drifted" != "0" ]; then
  echo "bootstrap: $drifted principal(s) are mapped to an object id that is no longer the identity they name." >&2
  echo "           An identity was probably deleted and recreated. The role cannot simply be dropped" >&2
  echo "           while it owns objects; see the README." >&2
  exit 1
fi

# A workload principal has to be a service principal and must not be an administrator. A role
# created with is_admin true is a member of azure_pg_admin, which is the server-wide reach this
# whole directory exists to keep away from applications, and a type other than service means the
# role is bound to something other than the managed identity it is named after. Neither shows up
# as a failure until something is exploited, so they are gated here. The administrator group is
# excluded deliberately: it is legitimately a group and legitimately an administrator.
misconfigured=$(psql "$connection" -tAc "
  SELECT count(*)
  FROM (VALUES ${expected_rows}) AS e (role_name, object_id)
  LEFT JOIN pgaadauth_list_principals(false) p ON p.rolname = e.role_name
  WHERE p.rolname IS NULL
     OR p.principaltype <> 'service'
     OR p.isadmin <> 0;
")

if [ "$misconfigured" != "0" ]; then
  echo "bootstrap: $misconfigured workload principal(s) are missing, are not service principals, or" >&2
  echo "           are administrators. Run this as the administrator to see which:" >&2
  echo "             SELECT * FROM pgaadauth_list_principals(false);" >&2
  exit 1
fi

# Azure itself makes the configured Entra administrator group a member of Entra-created
# workload roles. On this server those memberships are granted by azuresu with ADMIN OPTION.
# They are part of Azure's administrative model and are therefore expected.
#
# What must not exist is any *other* role membership into a workload identity. Such a membership
# can confer a workload's access without adding anything to the database ACL; for example,
# granting the delivery runtime identity to the ordering runtime identity could let ordering
# inherit delivery's privileges.
#
# This check therefore ignores only the configured administrator group and rejects every other
# direct membership in a workload role. The effective-access matrix below separately verifies
# what each workload identity can actually CONNECT to, including inherited access.
members=$(psql "$connection" -tAc "
  SELECT format('%s is a member of %s', m.rolname, r.rolname)
  FROM pg_auth_members a
  JOIN pg_roles r ON r.oid = a.roleid
  JOIN pg_roles m ON m.oid = a.member
  JOIN (VALUES ${workload_role_rows}) AS w (rolname) ON w.rolname = r.rolname
  WHERE m.rolname <> '${admin_role}'
  ORDER BY r.rolname, m.rolname;
")

if [ -n "$members" ]; then
  echo "bootstrap: a non-admin role has been granted membership in a workload identity:" >&2
  while IFS= read -r membership; do
    printf '           %s\n' "$membership" >&2
  done <<<"$members"
  echo "           That membership can confer workload access without a direct database grant." >&2
  echo "           Review and revoke it before relying on the service/database boundary." >&2
  echo "           Azure-managed memberships for ${admin_role} are intentionally exempt." >&2
  exit 1
fi

# The boundary between the two applications. CONNECT is granted on every database to PUBLIC by
# default and roles are cluster-wide, so without the revokes in 02-database-grants.sql the
# ordering identities could open the delivery databases and the identities would be names
# rather than boundaries.
#
# A database's owner is part of the expected set rather than an exemption: PostgreSQL gives an
# owner every privilege implicitly and it cannot be taken away, so demanding that the owner holds
# no CONNECT would fail every run. It is printed at the end so the owner is in plain sight.
#
# The expectation is exact in both directions for every other role: a database that cannot be
# connected to by one of its identities is as much a fault as one that can be connected to by
# anybody else. aclexplode expands the ACL rather than matching its text, and acldefault fills in
# the ACL of a database nobody has granted on — the state that still admits PUBLIC, so leaving it
# out would skip the case worth catching. A cronus database that is not in the model at all is
# reported too, because nothing has locked it down.
connect_problems=$(psql "$connection" -tAc "
  WITH model_connect (datname, rolname) AS (VALUES ${expected_connect_rows}),
       model_database (datname) AS (VALUES ${expected_database_rows}),
       cronus_database AS (
         SELECT d.datname, coalesce(o.rolname, 'PUBLIC') AS owner_name
         FROM pg_database d
         LEFT JOIN pg_roles o ON o.oid = d.datdba
         WHERE d.datname LIKE 'cronus\_%'
       ),
       expected_connect AS (
         SELECT datname, rolname FROM model_connect
         UNION
         SELECT datname, owner_name FROM cronus_database
       ),
       actual_connect AS (
         SELECT d.datname, coalesce(r.rolname, 'PUBLIC') AS rolname
         FROM pg_database d
         CROSS JOIN LATERAL aclexplode(coalesce(d.datacl, acldefault('d', d.datdba))) AS a
         LEFT JOIN pg_roles r ON r.oid = a.grantee
         WHERE d.datname LIKE 'cronus\_%'
           AND a.privilege_type = 'CONNECT'
       )
  SELECT format('%s: %s', problem, datname)
  FROM (
    SELECT 'is in the model but does not exist, so nothing has locked it down' AS problem,
           e.datname, NULL::text AS rolname
    FROM model_database e
    WHERE NOT EXISTS (SELECT 1 FROM cronus_database c WHERE c.datname = e.datname)

    UNION ALL
    SELECT 'exists but is not in the model, so nothing has locked it down', c.datname, NULL::text
    FROM cronus_database c
    WHERE NOT EXISTS (SELECT 1 FROM model_database m WHERE m.datname = c.datname)

    UNION ALL
    SELECT 'cannot connect as ' || e.rolname, e.datname, e.rolname
    FROM expected_connect e
    WHERE NOT EXISTS (
      SELECT 1 FROM actual_connect c WHERE c.datname = e.datname AND c.rolname = e.rolname
    )

    UNION ALL
    SELECT 'can connect as ' || c.rolname || ', which is not in the model',
           c.datname, c.rolname
    FROM actual_connect c
    WHERE NOT EXISTS (
      SELECT 1 FROM expected_connect e WHERE e.datname = c.datname AND e.rolname = c.rolname
    )
  ) AS problems
  ORDER BY datname;
")

if [ -n "$connect_problems" ]; then
  echo "bootstrap: the CONNECT grants are not what the model expects:" >&2
  while IFS= read -r problem; do
    printf '           %s\n' "$problem" >&2
  done <<<"$connect_problems"
  echo "           Without this, an ordering identity can reach the delivery data and the" >&2
  echo "           identities are names rather than boundaries." >&2
  exit 1
fi

# Check effective CONNECT access too: memberships, nested grants and PUBLIC can bypass the ACL matrix.
access_problems=$(psql "$connection" -tAc "
  WITH model_connect (datname, rolname) AS (VALUES ${workload_connect_rows}),
       workload_role (rolname) AS (VALUES ${workload_role_rows}),
       model_database (datname) AS (VALUES ${expected_database_rows}),
       effective AS (
         SELECT r.rolname,
                d.datname,
                has_database_privilege(r.rolname, d.datname, 'CONNECT') AS can_connect,
                EXISTS (
                  SELECT 1 FROM model_connect m
                  WHERE m.datname = d.datname AND m.rolname = r.rolname
                ) AS should_connect
         FROM workload_role r
         CROSS JOIN model_database d
       )
  SELECT CASE
           WHEN should_connect
             THEN format('%s cannot connect to its own database %s', rolname, datname)
           ELSE format('%s can connect to %s, which is not its own', rolname, datname)
         END
  FROM effective
  WHERE can_connect IS DISTINCT FROM should_connect
  ORDER BY datname, rolname;
")

if [ -n "$access_problems" ]; then
  echo "bootstrap: effective access is not what the model expects:" >&2
  while IFS= read -r problem; do
    printf '           %s\n' "$problem" >&2
  done <<<"$access_problems"
  echo "           A database ACL can look exactly right while a role reaches it anyway, through a" >&2
  echo "           membership, a nested membership, an owner, or PUBLIC. This is the answer that" >&2
  echo "           actually decides whether the boundary holds." >&2
  exit 1
fi

# A database owner implicitly holds CREATE even after revokes.
# Reject runtime ownership so CONNECT checks cannot hide a breach of the runtime/migration DDL boundary.
owner_problems=$(psql "$connection" -tAc "
  SELECT format('%s is owned by the workload identity %s', d.datname, o.rolname)
  FROM pg_database d
  JOIN pg_roles o ON o.oid = d.datdba
  JOIN (VALUES ${workload_role_rows}) AS w (rolname) ON w.rolname = o.rolname
  WHERE d.datname LIKE 'cronus\_%'
  ORDER BY d.datname;
")

if [ -n "$owner_problems" ]; then
  echo "bootstrap: a workload identity owns a database:" >&2
  while IFS= read -r problem; do
    printf '           %s\n' "$problem" >&2
  done <<<"$owner_problems"
  echo "           The owner of a database holds every privilege on it, so that identity can create" >&2
  echo "           schema objects whatever the grants say." >&2
  exit 1
fi

echo "    principals are service principals and none is an administrator"
echo "    no non-admin role is a member of a workload identity"
echo "    each workload identity can connect to its own database and to no other Cronus database"
echo "    database ACLs contain only the expected workload identities, admin group, and owner"
psql "$connection" -tAc "
  SELECT format('      %s is owned by %s', d.datname, coalesce(o.rolname, 'PUBLIC'))
  FROM pg_database d
  LEFT JOIN pg_roles o ON o.oid = d.datdba
  WHERE d.datname LIKE 'cronus\_%'
  ORDER BY d.datname;"
echo
echo "bootstrap: done"
