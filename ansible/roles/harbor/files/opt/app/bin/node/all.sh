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
  mkdir -p /data/registry
  if [ "$MY_ROLE" = "log" ]; then
    echo 'ubuntu:p12cHANgepwD' | chpasswd
    deluser ubuntu sudo || log Already removed user ubuntu from sudo.
    mkdir -p /var/log/harbor/job-logs
    chown -R 10000.10000 /var/log/harbor
    ln -s -f /opt/app/conf/log/logrotate.conf  /etc/logrotate.d/harbor-log.conf
    ln -s -f /opt/app/conf/nfs-server/exports  /etc/exports
  fi

  if [ "$MY_ROLE" = "storage" ]; then 
    ensureNfsModulesLoaded; 
    ln -s -f /opt/app/conf/nfs-server/exports /etc/exports
  fi
}

initCluster() {
  if [ "$MY_ROLE" = "log" ]; then
    rm -rf /var/log/harbor/lost+found
  fi

  if [ "$MY_ROLE" = "storage" ]; then
    # Harbor needs the ownership of the storage directory. See: https://github.com/goharbor/harbor/issues/3816
    chown -R 10000.10000 $serverMountPath

    # Allow clients write files
    chmod -R 777 $serverMountPath
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
  openssl genrsa -out /data/secret/core/private_key.pem 4096
  openssl req -new -x509 -key /data/secret/core/private_key.pem -subj '/C=CN/ST=Beijing/O=QingCloud/OU=AppCenter/CN=Harbor' -out /data/secret/registry/root.crt -days 3650
}

start() {
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
#example  
#password     7055c709338844684a03afd47eb99eaf (1.7.1)  901e944c153438064a68712fef73c2dd (1.9.3)  --> Harbor12345                           
#salt         7t3s93zk7qhcg7lqx1xm9meega26ryte          ne4triv6j6f5074ei7q36nbqvd1ow5pz
  docker exec -i db sh -c "psql -U postgres -d registry -c \"update harbor_user set password='ad07ad1d21fa0b43e48320256db73749',salt='2t5pyybr2mgtz6odecfbfdauh9637p6q',password_version='sha256' where username='admin';\""
}

cleanJobLogs() {
  local timeFlag=$(echo $@ | jq -r '.jobLogsDuration');
  if [[ "$timeFlag" != "0" ]]; then
    find /var/log/harbor/jobLogs -mtime +$[timeFlag - 1] -type f -delete
  else
    rm  /var/log/harbor/jobLogs/*
  fi
}