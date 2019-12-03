# Error codes
EC_DEFAULT=1 # default
EC_LOGGING=2 # logging: failed to log remotely
EC_CHECK_SVCS=3 # healthcheck: some Docker services not running
EC_CHECK_PORT=4 # healthcheck: some ports not listening
EC_CHECK_HEALTH=6
EC_RETRY_FAILED=5 # retry: failed several times
EC_UPGRADE_DB_NO_MOUNT=10 # upgrade failure: no DB data directory mount
EC_UPGRADE_DISK_SPACE=11 # upgrade failure: no enough disk space (>33%)
EC_UPGRADE_DB_DIR_EXISTS=12 # upgrade failure: DB data directory is not empty
EC_UPGRADE_DB_NO_DIR=13 # upgrade failure: no DB data directory mount
EC_UPGRADE_TO_130=20 # upgrade failure: DB migration to Harbor v1.3.0
EC_UPGRADE_TO_160=21 # upgrade failure: DB migration to Harbor v1.6.0
EC_UPDATE_DB_PWD_INIT=22 # upgrade failure: DB create container to update to random super password
EC_UPDATE_DB_PWD_START=23 # upgrade failure: DB container failed to start
EC_UPDATE_DB_PWD_RUN=24 # upgrade failure: DB update to random super password
EC_UPDATE_DB_PWD_STOP=25 # upgrade failure: DB remove the container

clientMountPath=/data/registry
ensureRegistryMounted() {
  [[ -n "$STORAGE_NODE_IP" ]] || return 0

  if ! grep -qs "$clientMountPath " /proc/mounts; then
    local mountSrc="$STORAGE_NODE_IP:/data/registry"
    log "Mounting '$mountSrc' for registry ..."
    mkdir -p $clientMountPath
    mount $mountSrc $clientMountPath
    touch $clientMountPath && log Successfully mounted!
  fi
  mount  ${LOG_NODE_IP}:/var/log/harbor/job_logs    /data/job_logs 
}

ensureNfsModulesLoaded() {
  modprobe nfs
  modprobe nfsd
}

dockerCompose() {
  docker-compose --env-file /opt/app/bin/envs/harbor.env -f /opt/app/conf/docker-compose.yml $@
}

serverMountPath=/data/registry
dbMountDir=/data/database
dbDataDir=$dbMountDir/app-1.2.0
initNode() {
  _initNode

  if [ "$MY_ROLE" = "log" ]; then
    echo 'ubuntu:p12cHANgepwD' | chpasswd
    deluser ubuntu sudo || log Already removed user ubuntu from sudo.
  fi

  if [ "$MY_ROLE" = "storage" ]; then ensureNfsModulesLoaded; fi
}

initCluster() {
  if [ "$MY_ROLE" = "log" ]; then
    rm -rf /var/log/harbor/lost+found
    ln -s -f /opt/app/conf/log/logrotate.conf  /etc/logrotate.d/joblogs.conf
    ln -s -f /opt/app/conf/nfs-server/exports /etc/exports
  fi

  if [ "$MY_ROLE" = "storage" ]; then
    # Harbor needs the ownership of the storage directory. See: https://github.com/goharbor/harbor/issues/3816
    chown -R 10000.10000 $serverMountPath

    # Allow clients write files
    chmod -R 777 $serverMountPath
    ln -s -f /opt/app/conf/nfs-server/exports /etc/exports
  fi

  if [ "$MY_ROLE" = "db" ]; then
    rm -rf $dbMountDir/lost+found
    mkdir -p $dbDataDir
    chown -R 999.999 $dbDataDir
  fi
}

init() {
  initCluster
}

createKeys() {
  if [ "$MY_SID" == "1" ]; then
    openssl genrsa -out /tmp/key.pem 4096
    openssl req -new -x509 -key /tmp/key.pem -subj '/C=CN/ST=Beijing/O=QingCloud/OU=AppCenter/CN=Harbor' -out /tmp/cert.pem -days 3650
    echo -n "$(cat /tmp/key.pem | base64 | tr -d '\n') $(cat /tmp/cert.pem | base64 | tr -d '\n')"
    rm -rf /tmp/*.pem
  fi
}

start() {
  if [[ "$MY_ROLE" =~ ^(web|job)$ ]]; then ensureRegistryMounted; fi
  _start
  retry 60 2 0 execute check
}

reload() {
  isNodeInitialized || return 0

  if [[ " $@ " =~ " $MY_ROLE " ]]; then
    execute restart
  else
    _reload $@
  fi
}

checkContainerHealthy() {
  local status; status=$(docker inspect --format '{{.State.Health.Status}}' $1)
  if [ "$status" != "healthy" ]; then return $EC_CHECK_HEALTH; fi
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
  docker run --rm -di --name update-passwd --env-file=/opt/app/conf/db/env -v $dbDataDir:/var/lib/postgresql/data goharbor/harbor-db:$HARBOR_VERSION || return $EC_UPDATE_DB_PWD_INIT
  retry 30 2 0 checkContainerHealthy update-passwd || return $EC_UPDATE_DB_PWD_START
  docker exec -i update-passwd sh -c "psql -U postgres -c \"alter user postgres with password '\$POSTGRES_PASSWORD'\"" || return $EC_UPDATE_DB_PWD_RUN
  docker stop update-passwd || return $EC_UPDATE_DB_PWD_STOP
}

upgrade() {
  if [ "$MY_ROLE" = "db" ]; then
    [ -d $dbMountDir ] || return $EC_UPGRADE_DB_NO_DIR

    if [ -f "$dbMountDir/ibdata1" ]; then
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

      local oldFiles=`realpath $dbMountDir/*`
      for oldFile in $oldFiles; do
        [ "$oldFile" = "$dbDataDir" ] || rm -rf "$oldFile"
      done

    else
      [ -d "$dbDataDir" ] || return $EC_UPGRADE_DB_NO_DIR
    fi
  fi
}

checkServices() {
  requiredCount=`dockerCompose config --services | wc -l`
  runningCount=`docker ps --format "{{ .Status }}" | grep -E "Up[^(]*(\(healthy\))?$" | wc -l`
  [ $runningCount = $requiredCount ] || {
    log Running/Required containers: $runningCount/$requiredCount.
    return $EC_CHECK_SVCS
  }
}

check() {
  _check
  if [ "$MY_ROLE" != "storage" ]; then
  checkServices
  fi
}

resetAdminPwd() {
  [[ -n "/data/database/app-1.2.0/resetAdminPwd.sh" ]] || { 
    cp /opt/app/bin/node/resetAdminPwd.sh /data/database/app-1.2.0/resetAdminPwd.sh
    }
  docker exec -i  db sh -c "/var/lib/postgresql/data/resetAdminPwd.sh"
}