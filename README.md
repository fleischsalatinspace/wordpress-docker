# wordpress-docker

[![Shellcheck](https://github.com/fleischsalatinspace/wordpress-docker/workflows/shellcheck/badge.svg)](https://github.com/fleischsalatinspace/wordpress-docker/actions)

Easy to use docker-compose managed multi-container setup for running wordpress

1. [Features](#Features)
2. [Requirements](#Requirements)
3. [docker-compose modes](#docker-compose-modes)
    1. [Production](#Production)
    2. [Development](#Development)
4. [Administration](#Administration)
5. [Install](#Install)
    1. [Production](#Production)
    2. [Development](#Development)

## Features
This repository contains files for running wordpress within a docker-compose managed multi-container setup, based on the [official docker community image](https://hub.docker.com/_/wordpress)  To enable non-tech savy people to use this repository, there are [administration scripts](#Administration) for tasks like starting, stopping and backups included. Two docker-compose modes are available: production and develop. Check [below](#docker-compose-modes) for further information

## Requirements
- Ubuntu 18.04 or 20.04
- Docker Engine 20.10
- docker-compose 1.27.4

## docker-compose modes
### Production
- This mode is intended for running wordpress in a production environment.
- Beside listed requirements you need:
- - Domain
- - A/AAAA records pointing to your serverip
- TLS certificates will be provided from Lets Encrypt

### Development
- This mode runs a local wordpress instance to test this project or develop plugins.
- Beside listed requirements you need:
- - Modified hostsfile with `wordpress.lan` pointing to `127.0.0.1`
-  TLS certificate will be a self-signed caddy-internal

## Administration
- There are two docker-compose wrapper scripts included:
- - `production.sh` is a wrapper for `docker-compose -f docker-compose-prod.yml --env=.env.prod`
- - `develop.sh` is a wrapper for `docker-compose -f docker-compose-dev.yml --env=.env.dev`
- The wrapper scripts pass every argument to `docker-compose`, just with modified `docker-compose` file location and `.env` file location. Run the script without arguments to display help and available commands
- Available commands
- - backup: creates a backup of the mysql database and container volumes
- - restore: restores mysql database and container volumes from a provided backup
- - support-zip: creates a file containing application and service logs
- - up -d: start docker containers
- - stop: stop running docker containers
- - down: stop and remove docker containers
- - down -v: remove docker containers and volumes including application data. Use with care
- - logs -f: display logs for running containers
- - ps: display status of docker containers
- - --help: display docker-compose help
-  Planned functions are
- - Viewing application/webserver logs from volumes instead of docker-compose logs -f

# Install
## Production
1. Clone this repo and change directory
2. Copy the example `.env.sample` file to `.env.prod`
3. Copy the example `config/Caddyfile.sample` file to `config/Caddyfile-prod`
4. Edit `.env.prod` and `config/Caddyfile-prod` and check your config with `./production.sh config`
5. If satisfied, start up your instance with `./production.sh up -d` 
6. If youre getting the wordpress setup page with letsencrypt staging TLS-certificate , everything is working
7. Stop the cluster with `./production.sh stop` and comment `acme_ca` in `config/Caddyfile-prod` to receive live letsencrypt TLS-certificate
8. Start  cluster with `./production.sh up -d`

## Development
1. Clone this repo and change directory
2. Copy the example `.env.sample` file to `.env.dev`
3. Copy the example `config/Caddyfile.sample` file to `config/Caddyfile-dev`
4. Edit `.env.dev` and `config/Caddyfile-dev` and check your config with `./develop.sh config`
5. Start your instance with `./develop.sh up -d`
6. Access your instance on `https://wordpress.lan`

# Setup wordpress
1. Navigate to your wordpress page and follow instructions.

# Updating wordpress
- use Webfrontend

Feel free to contribute, there are many improvements (check TODO strings in this repository) that still need to be made. 
