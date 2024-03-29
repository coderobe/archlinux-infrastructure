#!/bin/bash
set -e

## Set the old version that we want to upgrade from.
TO_VERSION=$(pacman -Q postgresql | grep -Po '(?<=postgresql )[0-9]+\.[0-9]')
to_major=$(echo "$TO_VERSION" | awk -F'.' '{print $1}')
to_minor=$(echo "$TO_VERSION" | awk -F'.' '{print $2}')
if [[ ${to_major} -ne 11 ]]; then
	# NOTE: When this happens you should check the changelog and add any
	# necessary changes here. Then bump the version check.
	echo "WARNING: major upgrade detected, aborting..."
	exit 1
fi
export FROM_VERSION="$(cat /var/lib/postgres/data/PG_VERSION)"

if [[ "$FROM_VERSION" == "$TO_VERSION" ]]; then
	echo "WARNING: from and to versions are equal. Have you already updated?! Aborting..."
	exit 1
fi

# free space check
used_space=$(df --local --output=pcent /var/lib/postgres/ | grep -Po '[0-9]{1,3}(?=%)')
if [[ ${used_space} -ge 50 ]]; then
	echo "ERROR: not enough free space for upgrade with backup, aborting..."
	exit 2
fi

pacman -S --needed postgresql-old-upgrade
chown postgres:postgres /var/lib/postgres/
if [[ -d "/var/lib/postgres/data-${FROM_VERSION}" ]]; then
	echo "ERROR: backup data-${FROM_VERSION} directory already exists, aborting..."
	exit 3
fi
su - postgres -c "mv /var/lib/postgres/data /var/lib/postgres/data-${FROM_VERSION}"
su - postgres -c 'mkdir /var/lib/postgres/data'
su - postgres -c "initdb --locale $LANG -E UTF8 -D /var/lib/postgres/data"
vimdiff "/var/lib/postgres/data/pg_hba.conf" "/var/lib/postgres/data-${FROM_VERSION}/pg_hba.conf"
vimdiff "/var/lib/postgres/data/postgresql.conf" "/var/lib/postgres/data-${FROM_VERSION}/postgresql.conf"
for file in fullchain.pem chain.pem privkey.pem; do
	cp -avx "/var/lib/postgres/data-${FROM_VERSION}/$file" "/var/lib/postgres/data/$file"
done
systemctl stop postgresql.service
su - postgres -c "pg_upgrade -b /opt/pgsql-${FROM_VERSION}/bin/ -B /usr/bin/ -d /var/lib/postgres/data-${FROM_VERSION} -D /var/lib/postgres/data"
systemctl daemon-reload
systemctl start postgresql.service
su - postgres -c '/var/lib/postgres/analyze_new_cluster.sh'
# We probably want to manually delete things for now in case this script misses
# some stuff
#su - postgres -c '/var/lib/postgres/delete_old_cluster.sh'
