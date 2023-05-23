# Error codes
EC_DEFAULT=1 # default
EC_LOGGING=2 # logging: failed to log remotely
EC_CHECK_SVCS=3 # healthcheck: some Docker services not running
EC_CHECK_PORT=4 # healthcheck: some ports not listening
EC_CHECK_HEALTH=6
EC_RETRY_FAILED=5 # retry: failed several times
EC_UPGRADE_DB_NO_MOUNT=10 # upgrade failure: no DB data directory mount
EC_UPGRADE_DISK_SPACE=11 # upgrade failure: no enough disk space (>33%)
EC_UPGRADE_DB_DIR_NOT_EXISTS=12 # upgrade failure: DB data directory is not empty
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
  docker-compose --env-file /opt/app/current/bin/envs/harbor.env -f /opt/app/current/conf/docker-compose.yml $@
}

oldVersion=harbor-v2.2.1
serverMountPath=/data/registry
dbMountDir=/data/database
dbDataDir=$dbMountDir/harbor-$HARBOR_VERSION
initNode() {
  _initNode
  mkdir -p /data/registry
  if [ "$MY_ROLE" = "log" ]; then
    echo 'ubuntu:p12cHANgepwD' | chpasswd
    deluser ubuntu sudo || log Already removed user ubuntu from sudo.
    mkdir -p /var/log/harbor/job-logs
    chown -R 10000.10000 /var/log/harbor
    mkdir -p /var/log/harbor/trivy-data/reports
    mkdir -p /var/log/harbor/trivy-data/trivy
    chown -R 10000.10000 /var/log/harbor/trivy-data
    ln -s -f /opt/app/current/conf/log/logrotate.conf  /etc/logrotate.d/harbor-log.conf
    ln -s -f /opt/app/current/conf/nfs-server/exports  /etc/exports
  fi

  if [ "$MY_ROLE" = "storage" ]; then 
    ensureNfsModulesLoaded; 
    ln -s -f /opt/app/current/conf/nfs-server/exports /etc/exports
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

  _initCluster
}

init() {
  initCluster
}

createKeys() {
  openssl genrsa -out /data/secret/core/private_key.pem 4096
  openssl req -new -x509 -key /data/secret/core/private_key.pem -subj '/C=CN/ST=Beijing/O=QingCloud/OU=AppCenter/CN=Harbor' -out /data/secret/registry/root.crt -days 3650
}

start() {
  if ! isClusterInitialized; then
    log "fix for heath checking: init cluster first"
    initCluster
  fi

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
  rm -rf $dbMountDir/lost+found
  mkdir -p $dbMountDir/harbor-v2.4.3
  mkdir -p $dbMountDir/back_up
  cp -r $dbMountDir/$oldVersion/* $dbMountDir/back_up/
  cp -r $dbMountDir/$oldVersion/* $dbMountDir/harbor-v2.4.3/
  chmod 700 $dbMountDir/harbor-v2.4.3/
  chown -R 999.999 $dbMountDir/harbor-v2.4.3/
}

revertDb() {
  rm -rf $dbDataDir
}

upgrade() {
  if [ "$MY_ROLE" = "db" ]; then
    [ -d $dbMountDir ] || return $EC_UPGRADE_DB_NO_DIR

    if [ -d "$dbMountDir/$oldVersion" ]; then
      echo About to upgrade. Checking volume usage ...
      used=$(df --output=pcent $dbMountDir | tail -1 | tr -d '%')
      [ $used -lt 33 ] || {
        echo Not enough disk volume for backup: $used% used. Make it to less than 33%.
        return $EC_UPGRADE_DISK_SPACE
      }

      echo Duplicating DB data ...
      duplicateDb

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
#still ok at 2.2.1
  docker exec -i harbor-db sh -c "psql -U postgres -d registry -c \"update harbor_user set password='ad07ad1d21fa0b43e48320256db73749',salt='2t5pyybr2mgtz6odecfbfdauh9637p6q',password_version='sha256' where username='admin';\""
}

cleanJobLogs() {
  local timeFlag=$(echo $@ | jq -r '.jobLogsDuration');
  if [[ "$timeFlag" != "0" ]]; then
    find /var/log/harbor/job-logs -mtime +$[timeFlag - 1] -type f -delete
  else
    find /var/log/harbor/job-logs -type f -delete
  fi
}