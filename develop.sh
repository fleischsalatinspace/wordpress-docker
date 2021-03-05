#!/usr/bin/env bash
#stolen from https://serversforhackers.com/dockerized-app/compose-separated
#TODO: check if we are in correct directory
#TODO: check if compose files are available
#TODO: eve-universe sql import function

# https://mywiki.wooledge.org/glob
# https://sipb.mit.edu/doc/safe-shell/
set -Eeuo pipefail
shopt -s failglob

# backup location
#BACKUP_LOCATION="/var/backups/"
BACKUP_LOCATION="/tmp/"

# Decide which docker-compose file to use
COMPOSE_FILE="dev"

# check if we are root, if not use sudo
SUDO=''
if [ "${EUID}" != "0" ]; then
    SUDO='sudo'
fi

# setup_colors for message function
setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}
setup_colors

# message function
msg() {
	echo >&2 -e "$(date +%H:%M:%S%z) ${1-}"
}

# Create docker-compose command to run
COMPOSE="docker-compose -f docker-compose-${COMPOSE_FILE}.yml --env=.env.${COMPOSE_FILE}"

backup() {
	BACKUP_LOCATION=${BACKUP_LOCATION}$(date +%F_%H-%M-%S)
        msg "Creating backup location at ${BACKUP_LOCATION}"
        if ! mkdir -p "${BACKUP_LOCATION}" ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to create backup location at ${BACKUP_LOCATION}. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully created backup location at ${BACKUP_LOCATION}"
	msg "Checking if docker containers are running"
	# dirty check if containers are not running
	if [[ $(${COMPOSE} ps | grep -c "Exit" ) -ne 0 ]] ; then
		msg "${RED}ERROR${NOFORMAT} Please start up docker containers before creating a backup"
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} docker containers are running"
        msg "Creating MySQL backup"
	if ! ${COMPOSE} exec db sh -c "exec mysqldump --all-databases -uroot -p\${MYSQL_ROOT_PASSWORD}" | sed -u "s/mysqldump\:\ \[Warning\]\ Using\ a\ password\ on\ the\ command\ line\ interface\ can\ be\ insecure\.//g" | gzip > "${BACKUP_LOCATION}/backup_all-databases.sql.gz" ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to create MySQL backup. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully created MySQL backup"
        msg "Stopping docker containers"
	if ! ${COMPOSE} stop >/dev/null 2>&1 ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to stop docker containers. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully stopped docker containers"
	# tar backup volumes
	for i in $(${COMPOSE} config --volumes);
       	do 
	  PWD_BASENAME=$(basename "$(pwd)")
	  BACKUP_TARGET=$(docker volume inspect --format '{{ .Mountpoint }}' "${PWD_BASENAME}_${i}")
          msg "Creating docker container volume backup of ${i}"
	  if ! ${SUDO} tar cvfz "${BACKUP_LOCATION}"/"${i}".tar.gz -C "${BACKUP_TARGET}"/ . >/dev/null 2>&1 ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to create backup of container volume ${i}. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	  fi
	  msg "${GREEN}OK${NOFORMAT} Successfully created backup of ${i} volume"
        done
}

restore() {
	if [ -z "${*}" ]; then
        	msg "${RED}ERROR${NOFORMAT} No valid input detected. Please provide full path to a backup location. ${YELLOW}Execute bash -x \$yourscriptfilename.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	verify_backup "$@"
	RESTORE_TAR_PATH="${*}"
        msg "Stopping docker containers"
	if ! ${COMPOSE} stop >/dev/null 2>&1 ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to stop docker containers. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully stopped docker containers"
	# verifying container volume path and clearing contents
        for volumename in $(${COMPOSE} config --volumes | grep -v database);
        do
          PWD_BASENAME=$(basename "$(pwd)")
          RESTORE_TARGET=$(docker volume inspect --format '{{ .Mountpoint }}' "${PWD_BASENAME}_${volumename}")
          msg "${YELLOW}WARN${NOFORMAT} Removing old docker volume data of ${volumename}"
	  # check if RESTORE_TARGET is a directory
	  if ! ${SUDO} [ -d "${RESTORE_TARGET}" ]; then
                  msg "${RED}ERROR${NOFORMAT} Invalid docker container volume path. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"
		  exit 1
          fi
	  # iterate over restore targets and remove content of directory after user confirmation
	  # we have to implement optional sudo, so shellglob style is not possible
	  # https://mywiki.wooledge.org/BashPitfalls#for_f_in_.24.28ls_.2A.mp3.29
	  # https://mywiki.wooledge.org/UsingFind#Actions_in_bulk:_xargs.2C_-print0_and_-exec_.2B-
	  # if find return empty string, just skip removal
	  if [ -n "$(${SUDO} find "${RESTORE_TARGET}" -maxdepth 1 -mindepth 1 -print)" ] ; then
		# find did return non-empty string, so lets iterate over it
	  	for data in $(${SUDO} find "${RESTORE_TARGET}" -maxdepth 1 -mindepth 1 -print);
          	do 
	  	      # make sure return data from find is non-zero
	  	      if [ -n "${data}" ] || [ "${data}" != "" ]; then
			        # remove data
          			if ! ${SUDO} rm -vr "${data}" ; then
          			      msg "${RED}ERROR${NOFORMAT} Failed to remove container volume data ${data}. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"
          			      exit 1
          			fi
          			msg "${GREEN}OK${NOFORMAT} Successfully removed container volume data of ${volumename}"
	  	      fi
          	done
	  else
		msg "${GREEN}OK${NOFORMAT} Container volume data seems empty. Skipping data removal."
	  fi
        done
	# TODO: check if container volumes exist, if not fail and advise to up -d first
	# restore backup volumes excluding database volume
	for i in $(${COMPOSE} config --volumes | grep -v database);
       	do 
	  PWD_BASENAME=$(basename "$(pwd)")
	  RESTORE_TARGET=$(docker volume inspect --format '{{ .Mountpoint }}' "${PWD_BASENAME}_${i}")
          msg "Restoring docker container volume backup of ${i}"
	  if ! ${SUDO} tar -C "${RESTORE_TARGET}"/ -vz -xf "${RESTORE_TAR_PATH}"/"${i}".tar.gz >/dev/null 2>&1 ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to restore backup of container volume ${i}. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	  fi
	  msg "${GREEN}OK${NOFORMAT} Successfully restored backup of ${i} volume"
        done
        msg "Starting MySQL docker container"
	if ! ${COMPOSE} up -d db >/dev/null 2>&1 ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to start MySQL docker container. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully started MySQL docker containers"
        msg "Restoring MySQL backup"
	if ! gunzip < "${RESTORE_TAR_PATH}"/backup_all-databases.sql.gz | ${COMPOSE} exec -T db sh -c "exec mysql -uroot -p\${MYSQL_ROOT_PASSWORD}" ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to restore MySQL backup. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully restored MySQL backup"
        msg "Starting docker containers"
	if ! ${COMPOSE} up -d >/dev/null 2>&1 ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to start docker containers. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully started docker containers"
      
}

verify_backup() {
	ARCHIVE_PATH="${1}"
	msg "Verifying backup directory"
	if ! [ -d "${ARCHIVE_PATH}" ]; then
		msg "${RED}ERROR${NOFORMAT} Failed to verify backup directory. ${YELLOW}Execute bash -x \$yourscriptfilename.sh for debugging.${NOFORMAT}"
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully verified backup directory"
	for i in $(${COMPOSE} config --volumes);
       	do 
          msg "Verifying backup file of ${i}"
	  if ! ${SUDO} tar tzfv "${ARCHIVE_PATH}"/"${i}".tar.gz >/dev/null 2>&1 ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to verify backup file of ${i}. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	  fi
	  msg "${GREEN}OK${NOFORMAT} Successfully verified backup file of ${i}"
        done
        msg "Verifying database backup file"
	if ! ${SUDO} gzip -t -v "${ARCHIVE_PATH}"/backup_all-databases.sql.gz >/dev/null 2>&1 ; then
              msg "${RED}ERROR${NOFORMAT} Failed to verify backup file of ${i}. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
	      exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully verified database backup file"
	
}

support-zip() {
	BACKUP_LOCATION=${BACKUP_LOCATION}$(date +%F_%H-%M-%S)_support-zip
        msg "Creating support-zip location at ${BACKUP_LOCATION}"
        if ! mkdir -p "${BACKUP_LOCATION}" ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to create support-zip location at ${BACKUP_LOCATION}. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully created support-zip location at ${BACKUP_LOCATION}"
	# export docker mysql db container logs 
        msg "Creating database container logs export"
	if ! ${COMPOSE} logs --no-color -t db | gzip >> "${BACKUP_LOCATION}"/database.log.gz ; then
               msg "${RED}ERROR${NOFORMAT} Failed to create database container log export. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
               exit 1
        fi
        msg "${GREEN}OK${NOFORMAT} Successfully created database container log export"	
        msg "Stopping docker containers"
	if ! ${COMPOSE} stop >/dev/null 2>&1 ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to stop docker containers. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	fi
	msg "${GREEN}OK${NOFORMAT} Successfully stopped docker containers"
	# tar backup logs volumes
	for i in $(${COMPOSE} config --volumes | grep logs);
       	do 
	  PWD_BASENAME=$(basename "$(pwd)")
	  BACKUP_TARGET=$(docker volume inspect --format '{{ .Mountpoint }}' "${PWD_BASENAME}_${i}")
          msg "Creating docker container volume backup of ${i}"
	  if ! ${SUDO} tar cvfz "${BACKUP_LOCATION}"/"${i}".tar.gz -C "${BACKUP_TARGET}"/ . >/dev/null 2>&1 ; then
        	msg "${RED}ERROR${NOFORMAT} Failed to create backup of container volume ${i}. ${YELLOW}Execute bash -x \$yourscriptfile.sh for debugging.${NOFORMAT}"  
		exit 1
	  fi
	  msg "${GREEN}OK${NOFORMAT} Successfully created backup of ${i} volume"
        done
}

# If we pass any arguments...
if [ $# -gt 0 ];then
    # "backup" 
    if [ "$1" == "backup" ]; then
        #shift 1
	echo -e "This will backup your MySQL database and then backup every container volume. In this process your pathfinder will be ${RED}stopped${NOFORMAT}.\nDo you want to continue?"
        select yn in "Yes" "No"; do
            case ${yn} in
                Yes ) backup; break;;
                No ) exit;;
		* ) exit;;
            esac
        done
    elif [ "$1" == "restore" ]; then
        shift 1
	echo -e "This will restore a backup of your MySQL database and then restore every container volume. In this process ${RED}your pathfinder will be stopped${NOFORMAT} and ${RED}all current data in the volumes will be lost.${NOFORMAT}\nDo you want to continue?"
        select yn in "Yes" "No"; do
            case ${yn} in
                Yes ) restore "$@"; break;;
                No ) exit;;
		* ) exit;;
            esac
        done
    elif [ "$1" == "support-zip" ]; then
        #shift 1
	echo -e "This will create a support-zip containing application logs for further analyzing. No user data or API keys are included. In this process ${RED}your pathfinder will be stopped${NOFORMAT}.\nDo you want to continue?"
        select yn in "Yes" "No"; do
            case ${yn} in
                Yes ) support-zip; break;;
                No ) exit;;
		* ) exit;;
            esac
        done

    # Else, pass-thru args to docker-compose
    else
        ${COMPOSE} "$@"
    fi

else
    msg "${RED}ERROR${NOFORMAT} No commands received. Displaying script help and status of docker containers"
    msg "COMMANDS"
    msg "   backup: creates a backup of the mysql database and container volumes"
    msg "   restore: restores mysql database and container volumes from a provided backup"
    msg "   support-zip: creates a file containing application and service logs"
    msg "   up -d: start docker containers"
    msg "   stop: stop running docker containers"
    msg "   down: stop and remove docker containers"
    msg "   down -v: remove docker containers and volumes including application data. ${RED}Use with care${NOFORMAT}"
    msg "   logs -f: display logs for running containers"
    msg "   ps: display status of docker containers"
    msg "   --help: display docker-compose help\n"
    ${COMPOSE} ps
fi
