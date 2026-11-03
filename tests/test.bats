#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  export GITHUB_REPO=cosmoblonde/ddev-db-shrink

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p "${HOME}/tmp"
  export TESTDIR="$(mktemp -d "${HOME}/tmp/${PROJNAME}.XXXXXX")"
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  export CI=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success
}

health_checks() {
  run ddev db-shrink --help
  assert_success
  assert_output --partial "Usage: ddev db-shrink"

  # the plan changes nothing
  run ddev db-shrink --dry-run
  assert_success
  assert_output --partial "Volume     ${PROJNAME}-mariadb"
  assert_output --partial "Dry run, nothing changed."
}

# data for the shrink tests: a second database with its own collation, a routine, and a table in db
# that was filled and emptied again, so its file stays large
fill_databases() {
  run ddev mysql -uroot -proot -e "CREATE DATABASE second CHARACTER SET latin1 COLLATE latin1_german2_ci;
    CREATE TABLE second.t (id INT PRIMARY KEY, name VARCHAR(20));
    INSERT INTO second.t VALUES (1, 'one'), (2, 'two'), (3, 'three');
    CREATE FUNCTION second.answer() RETURNS INT DETERMINISTIC RETURN 42;
    CREATE DATABASE old_import;
    CREATE TABLE old_import.t (id INT);
    CREATE TABLE db.keep (id INT PRIMARY KEY, name VARCHAR(20));
    INSERT INTO db.keep VALUES (1, 'kept');
    CREATE TABLE db.big (id INT AUTO_INCREMENT PRIMARY KEY, pad VARCHAR(1000));
    INSERT INTO db.big (pad) VALUES (REPEAT('x', 1000));"
  assert_success
  for _ in $(seq 1 15); do
    run ddev mysql -uroot -proot -e "INSERT INTO db.big (pad) SELECT pad FROM db.big"
    assert_success
  done
  run ddev mysql -uroot -proot -e "DELETE FROM db.big"
  assert_success
}

volume_kb() {
  docker exec -u root "ddev-${PROJNAME}-db" du -sk /var/lib/mysql 2>/dev/null | cut -f1
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

@test "guards stop before anything is changed" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  run ddev mysql -e "CREATE TABLE db.keep (id INT); INSERT INTO db.keep VALUES (1)"
  assert_success

  # no terminal and no --confirm
  run ddev db-shrink --dir="${TESTDIR}/dumps"
  assert_failure
  assert_output --partial "no terminal to ask: pass --confirm=${PROJNAME}, nothing changed"

  run ddev db-shrink --dir="${TESTDIR}/dumps" --confirm=wrong-project
  assert_failure
  assert_output --partial "does not match the project name ${PROJNAME}, nothing changed"

  run ddev db-shrink --exclude=no_such_db
  assert_failure
  assert_output --partial "--exclude: there is no database no_such_db"

  run ddev db-shrink --no-such-option
  assert_failure
  assert_output --partial "unknown option --no-such-option"

  # data untouched, no dumps written
  run ddev mysql -N -B -e "SELECT COUNT(*) FROM db.keep"
  assert_output "1"
  assert_dir_not_exist "${TESTDIR}/dumps"
}

@test "shrink the volume and keep all data" {
  set -eu -o pipefail
  run ddev add-on get "${DIR}"
  assert_success
  fill_databases
  before=$(volume_kb)

  run ddev db-shrink --dir="${TESTDIR}/dumps" --exclude=old_import --confirm="${PROJNAME}"
  assert_success
  assert_output --partial "EXCLUDED: gone afterwards"
  assert_output --partial "all tables and routines are back"
  assert_output --partial "Dumps kept in ${TESTDIR}/dumps/${PROJNAME}/"

  after=$(volume_kb)
  echo "# volume ${before} kB -> ${after} kB" >&3
  [ "${after}" -lt "${before}" ]

  # data, routine and collation are back, the excluded database is gone
  run ddev mysql -N -B -e "SELECT name FROM db.keep WHERE id = 1"
  assert_output "kept"
  run ddev mysql -N -B -e "SELECT COUNT(*) FROM second.t"
  assert_output "3"
  run ddev mysql -N -B -e "SELECT second.answer()"
  assert_output "42"
  run ddev mysql -N -B -e "SELECT default_collation_name FROM information_schema.schemata WHERE schema_name = 'second'"
  assert_output "latin1_german2_ci"
  run ddev mysql -N -B -e "SHOW DATABASES LIKE 'old_import'"
  assert_output ""

  # dumps and restore commands are kept
  dumps=$(ls -d "${TESTDIR}/dumps/${PROJNAME}"/*)
  assert_file_exist "${dumps}/db.sql.gz"
  assert_file_exist "${dumps}/second.sql.gz"
  assert_file_not_exist "${dumps}/old_import.sql.gz"
  run cat "${dumps}/restore.txt"
  assert_output --partial "ddev import-db --database=second"
}
