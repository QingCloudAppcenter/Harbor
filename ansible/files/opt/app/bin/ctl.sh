#!/usr/bin/env bash

set -e

# Error codes
EC_DEFAULT=1 # default
EC_LOGGING=2 # logging: failed to log remotely
EC_CHECK_SVCS=3 # healthcheck: some Docker services not running
EC_CHECK_PORT=4 # healthcheck: some ports not listening
EC_RETRY_FAILED=5 # retry: failed several times
EC_UPGRADE_DB_DIR=10 # upgrade failure: no DB data directory mount
EC_UPGRADE_DISK_SPACE=11 # upgrade failure: no enough disk space (>33%)
EC_UPGRADE_DB_DIR_EXISTS=12 # upgrade failure: DB data directory is not empty
EC_UPGRADE_TO_130=20 # upgrade failure: DB migration to Harbor v1.3.0
EC_UPGRADE_TO_160=21 # upgrade failure: DB migration to Harbor v1.6.0
EC_UPDATE_DB_PWD_INIT=22 # upgrade failure: DB create container to update to random super password
EC_UPDATE_DB_PWD_START=23 # upgrade failure: DB container failed to start
EC_UPDATE_DB_PWD_RUN=24 # upgrade failure: DB update to random super password
EC_UPDATE_DB_PWD_STOP=25 # upgrade failure: DB remove the container

source /opt/app/bin/.env

command=$1
targetRoles=$2
[ -z "$targetRoles" ] || [[ ",$targetRoles," =~ ",$NODE_ROLE," ]] || exit 0

log() {
  local nodeOptions="-T -n log -P 1514 -t $NODE_ROLE.appctl"
  [ "$NODE_ROLE" != "log" ] || nodeOptions="-t harbor.appctl"
  logger $nodeOptions --id=$$ [cmd=$command roles=$targetRoles] "$@" || return $EC_LOGGING
}

clientMountPath=/data/registry
ensureRegistryMounted() {
  [[ -n "$STORAGE_NODE_IP" ]] || return 0

  if ! grep -qs "$clientMountPath " /proc/mounts; then
    local mountSrc="$STORAGE_NODE_IP:/registry"
    log "Mounting '$mountSrc' for registry ..."
    mkdir -p $clientMountPath
    mount $mountSrc $clientMountPath
    touch $clientMountPath && log Successfully mounted!
  fi
}

ensureNfsModulesLoaded() {
  modprobe nfs
  modprobe nfsd
}

dockerCompose() {
  /usr/local/bin/docker-compose -f /opt/app/conf/docker-compose.yml $@
}

retry() {
  local tried=0
  local maxAttempts=$1
  local interval=$2
  local cmd="${@:3}"
  local retCode=$EC_RETRY_FAILED
  while [ $tried -lt $maxAttempts ]; do
    sleep $interval
    tried=$((tried+1))
    $cmd && return 0 || {
      retCode=$?
      echo "'$cmd' ($tried) returned an error."
    }
  done

  echo "'$cmd' still returned errors after $tried attempts. Stopping ..." && return $retCode
}

startServices() {
  dockerCompose up -d
  retry 60 2 check
  log All services started.
}

serverMountPath=/data/registry
dbMountDir=/data/database
dbDataDir=$dbMountDir/app-1.2.0
init() {
  if [ "$NODE_ROLE" = "log" ]; then
    echo 'ubuntu:p12cHANgepwD' | chpasswd
    deluser ubuntu sudo || log Already removed user ubuntu from sudo.
  fi

  if [ "$NODE_ROLE" = "storage" ]; then
    # Harbor needs the ownership of the storage directory. See: https://github.com/goharbor/harbor/issues/3816
    chown -R 10000.10000 $serverMountPath

    # Allow clients write files
    chmod -R 777 $serverMountPath
  fi
}

start() {
  if [ "$NODE_ROLE" = "db" ]; then
    local oldFiles=`realpath $dbMountDir/*`
    for oldFile in $oldFiles; do
      [ "$oldFile" = "$dbDataDir" ] || rm -rf "$oldFile"
    done
  fi
  [ "$NODE_ROLE" != "storage" ] || ensureNfsModulesLoaded
  [[ ! "$NODE_ROLE" =~ ^(web|job)$ ]] || ensureRegistryMounted

  startServices
}

stop() {
  dockerCompose down
}

# Ensure the restart command runs only once at a time.
killOtherRestarts() {
  # This is triggered by "sh -c /opt/app/bin/ctl.sh restart", and there will be 2 processes.
  local parentPid=$(ps -o sid= -p $$)
  local otherPids=`ps -df | grep -E "/opt/app/bin/ctl.sh (start|restart|update)" | grep grep | grep -v $parentPid | awk '{print $2}'`
  [ -z "$formerPids" ] || (log "Killing processes [$otherPids] ..." && kill -9 $otherPids) || log Process $formerPids already exited.
}

restart() {
  killOtherRestarts
  stop && start
}

update() {
  [ "$(dockerCompose ps -q | wc -l)" -gt 0 ] && restart || return 0
}

checkContainer() {
  local status=$(docker inspect --format '{{.State.Health.Status}}' $1)
  [ "$status" = "healthy" ] || return 55
}

duplicateDb() {
  [ -d "$dbDataDir" ] && return $EC_UPGRADE_DB_DIR_EXISTS || echo Duplicating DB data directory.
  rm -rf $dbMountDir/lost+found
  local files=$(ls $dbMountDir)
  mkdir -p $dbDataDir
  for file in $files; do
    cp -r "$dbMountDir/$file" "$dbDataDir/$file"
  done
}

revertDb() {
  rm -rf $dbDataDir
}

migrateDb() {
  # Migrating to v1.3.0 ...
  echo -n "y" | docker run -i --rm -e DB_USR=root -e DB_PWD=root123 -v $dbDataDir:/var/lib/mysql vmware/harbor-db-migrator:1.3 up head || return $EC_UPGRADE_TO_130

  # Migrating to v1.6.0 ...
  echo -n "y" | docker run -i --rm -e DB_USR=root -e DB_PWD=root123 -v $dbDataDir:/var/lib/mysql goharbor/harbor-migrator:v1.6.0 --db up || return $EC_UPGRADE_TO_160

  # Replace default password with the generated stronger one for super user
  docker run --rm -di --name update-passwd --env-file=/opt/app/conf/db/env -v $dbDataDir:/var/lib/postgresql/data goharbor/harbor-db:v1.7.0 || return $EC_UPDATE_DB_PWD_INIT
  retry 30 2 checkContainer update-passwd || return $EC_UPDATE_DB_PWD_START
  docker exec -i update-passwd sh -c "psql -U postgres -c \"alter user postgres with encrypted password '\$POSTGRES_PASSWORD'\"" || return $EC_UPDATE_DB_PWD_RUN
  docker rm -f update-passwd || return $EC_UPDATE_DB_PWD_STOP
}

upgrade() {
  if [ "$NODE_ROLE" = "db" ]; then
    [ -d $dbMountDir ] || return $EC_UPGRADE_DB_DIR

    echo About to upgrade. Checking volume usage ...
    used=$(df --output=pcent $dbMountDir | tail -1 | tr -d '%')
    [ $used -lt 33 ] || {
      echo Not enough disk volume for backup: $used% used. Make it to less than 33%.
      return $EC_UPGRADE_DISK_SPACE
    }

    echo Duplicating DB data ...
    duplicateDb

    echo Migrating DB data ...
    migrateDb || {
      retcode=$?
      revertDb
      return $retcode
    }
  fi

  init
}

checkServices() {
  requiredCount=`dockerCompose config --services | wc -l`
  runningCount=`docker ps --format "{{ .Status }}" | grep -E "Up[^(]*(\(healthy\))?$" | wc -l`
  [ $runningCount = $requiredCount ] || {
    log Running/Required containers: $runningCount/$requiredCount.
    return $EC_CHECK_SVCS
  }
}

declare -A rolePorts
rolePorts+=( [log]=1514 [cache]=6379 [db]=5432 [storage]=2049 [web]=80 [job]=8080 )
checkPort() {
  local port=${rolePorts[$NODE_ROLE]}
  netstat -atnp | grep -E ":::$port +:::\* +LISTEN +" -q || {
    log "No listening on port $port."
    return $EC_CHECK_PORT
  }
}

check() {
  checkServices && checkPort
}

$command
