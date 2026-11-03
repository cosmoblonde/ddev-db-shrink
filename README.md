[![tests](https://github.com/cosmoblonde/ddev-db-shrink/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/cosmoblonde/ddev-db-shrink/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/cosmoblonde/ddev-db-shrink)](https://github.com/cosmoblonde/ddev-db-shrink/commits)
[![release](https://img.shields.io/github/v/release/cosmoblonde/ddev-db-shrink)](https://github.com/cosmoblonde/ddev-db-shrink/releases/latest)

# DDEV DB Shrink

* [Overview](#overview)
* [Installation](#installation)
* [Usage](#usage)
* [What happens](#what-happens)
* [Guards](#guards)
* [Limits](#limits)
* [Tests](#tests)
* [Credits](#credits)

## Overview

Database volumes of DDEV projects only grow. InnoDB never gives space back to the file system: `ibdata1`, the undo
logs and tables that were filled and emptied again keep their size, even after `DELETE`, `TRUNCATE` or a new import.
After months of reimporting dumps, a volume of several GB can hold a few hundred MB of data.

`ddev db-shrink` gets the space back: it dumps every database, removes the volume, starts the project with a fresh
one and reimports the dumps. It shows the plan first and changes nothing before you type the project name.

MariaDB and MySQL only.

## Installation

```bash
ddev add-on get cosmoblonde/ddev-db-shrink
```

No restart needed, it is a host command. Remove with `ddev add-on remove db-shrink`.

## Usage

```bash
ddev db-shrink --dry-run                 # show the plan only
ddev db-shrink                           # show the plan, ask for the project name, shrink
ddev db-shrink --exclude="old_import"    # do not restore this database, it is gone afterwards
ddev db-shrink --dir=/Volumes/backup     # put the dumps somewhere else
ddev db-shrink --confirm=my-project      # no question, for scripts
ddev db-shrink --delete-dumps            # delete the dumps after a successful reimport
```

Example plan:

```text
Project    my-project
Volume     my-project-mariadb, 6.2 GB on disk
Databases
  db                           412.0 MB    318 tables
  second                        18.3 MB     12 tables, 2 routines/events
  old_import                     1.1 GB     87 tables  EXCLUDED: gone afterwards
Dumps      /Users/me/ddev-db-shrink/my-project/20261103-201500
           free 48.2 GB, needs about 107.6 MB
Expected   the volume shrinks to roughly the data size (430.3 MB)
Note       the project restarts without post-start hooks; "ddev restart" runs them later
```

Keep the dumps outside the project directory. With Mutagen, dumps inside the project are synced into the container
and take the space a second time.

## What happens

1. Reads all databases except the system ones, with charset, collation, number of tables and routines/events.
2. Dumps every database with `mysqldump --single-transaction --routines --events --triggers` into
   `~/ddev-db-shrink/<project>/<time>/` and checks every dump: gzip intact and ending with `-- Dump completed`.
   Writes `databases.txt` (the state before) and `restore.txt` (`ddev import-db` commands for every dump).
3. `ddev stop`, `docker volume rm <volume>`, `ddev start --skip-hooks`.
4. Creates every database with its original charset and collation and imports its dump.
5. Compares the number of tables and routines/events with the state before and shows the volume size before and
   after.
6. Deletes the dumps with `--delete-dumps` or when you answer yes, otherwise keeps them.

Dump and import run directly in the db container instead of through `ddev export-db` / `ddev import-db`, so the dump
options (routines, events) and the original collation of each database are under the command's control.

## Guards

* Nothing is removed before every dump is complete and checked. A failing dump stops the command with the volume
  untouched.
* The volume name is read from the db container (the volume mounted at `/var/lib/mysql`) and must contain the project
  name.
* Confirmation means typing the project name. Without a terminal, `--confirm=<project>` is required.
* `--exclude` must name existing databases, so a typo cannot lose a database silently.
* Stops if the free space at the dump location is clearly too small.
* Once the volume is removed, every error prints where the dumps are and points to `restore.txt`.

## Limits

* Database users other than the DDEV defaults (`root`, `db`) do not survive; the plan lists them.
* Post-start hooks are skipped on the restart, so hooks that write to the database do not run against an empty one.
  `ddev restart` runs them afterwards.
* Docker Desktop on macOS may report the freed space with some delay.
* PostgreSQL is not supported.

## Tests

`tests/test.bats` follows the [DDEV add-on template](https://github.com/ddev/ddev-addon-template): it creates a
project, bloats a table, adds a second database with its own collation and a routine, shrinks the volume and checks
that it got smaller and that all data is back. A second test checks that the guards stop before anything is
changed. Locally, with `bats-core`, `bats-assert`, `bats-file` and `bats-support` installed:

```bash
bats ./tests/test.bats --filter-tags '!release'
```

## Credits

**Contributed and maintained by [cosmoblonde](https://github.com/cosmoblonde)**
