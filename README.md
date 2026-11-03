[![add-on registry](https://img.shields.io/badge/DDEV-Add--on_Registry-blue)](https://addons.ddev.com)
[![tests](https://github.com/cosmoblonde/ddev-db-shrink/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/cosmoblonde/ddev-db-shrink/actions/workflows/tests.yml?query=branch%3Amain)
[![last commit](https://img.shields.io/github/last-commit/cosmoblonde/ddev-db-shrink)](https://github.com/cosmoblonde/ddev-db-shrink/commits)
[![release](https://img.shields.io/github/v/release/cosmoblonde/ddev-db-shrink)](https://github.com/cosmoblonde/ddev-db-shrink/releases/latest)

# DDEV Db Shrink

## Overview

This add-on integrates Db Shrink into your [DDEV](https://ddev.com/) project.

## Installation

```bash
ddev add-on get cosmoblonde/ddev-db-shrink
ddev restart
```

After installation, make sure to commit the `.ddev` directory to version control.

## Usage

| Command | Description |
| ------- | ----------- |
| `ddev describe` | View service status and used ports for Db Shrink |
| `ddev logs -s db-shrink` | Check Db Shrink logs |

## Advanced Customization

To change the Docker image:

```bash
ddev dotenv set .ddev/.env.db-shrink --db-shrink-docker-image="ddev/ddev-utilities:latest"
ddev add-on get cosmoblonde/ddev-db-shrink
ddev restart
```

Make sure to commit the `.ddev/.env.db-shrink` file to version control.

All customization options (use with caution):

| Variable | Flag | Default |
| -------- | ---- | ------- |
| `DB_SHRINK_DOCKER_IMAGE` | `--db-shrink-docker-image` | `ddev/ddev-utilities:latest` |

## Credits

**Contributed and maintained by [@cosmoblonde](https://github.com/cosmoblonde)**
