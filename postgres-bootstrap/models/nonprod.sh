# shellcheck shell=bash

# The nonprod database model, read by bootstrap.sh.
#
# Sourced rather than executed: it is data, and the script that reads it is the program.
# Nothing here is a secret — a server name, a group name and a set of role names are all
# visible from the portal and from `SELECT * FROM pg_roles`.
#
# Every value here is read by bootstrap.sh rather than in this file, so shellcheck reports
# each of them as unused.
# shellcheck disable=SC2034
#
# Every value here has to agree with environments/nonprod:
#
#   resource_group, server  module.postgres, through postgres_server_name
#   admin_role              admin_groups.postgres_admins.name
#
# and with the identities the same configuration creates, because a role name that no
# longer names an identity is a principal that can never sign in.

resource_group=rg-cronus-nonprod
server=psql-cronus-nonprod
admin_role=grp-cronus-postgres-admins-nonprod

# One row per database, and the two identities that belong to it:
#
#   <database>:<runtime identity>:<migration identity>
#
# The runtime identity is the one the deployment runs as and the migration identity is the
# one the migration job runs as. They are different because what the migration identity is
# granted is the one thing the runtime identity must not have: the right to create and
# alter schema objects.
#
# The database names come from postgres_database_names in environments/nonprod, keyed
# ordering_dev and so on; the identity names are the values of workload_identity_names and
# migration_identity_names under the same keys.
databases=(
  "cronus_dev_ordering:id-ordering-dev:id-ordering-migrations-dev"
  "cronus_dev_delivery:id-delivery-dev:id-delivery-migrations-dev"
  "cronus_staging_ordering:id-ordering-staging:id-ordering-migrations-staging"
  "cronus_staging_delivery:id-delivery-staging:id-delivery-migrations-staging"
)
