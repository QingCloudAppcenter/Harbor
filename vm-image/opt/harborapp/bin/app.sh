#!/usr/bin/env bash

source /opt/harbor/bin/env.sh
nodeRole=${NODE_ROLE%_node}
[[ ",$2," =~ ",$nodeRole," ]] || exit 0

# ======== Common ======== #
clientMountPath=/data/registry

ensureRegistryMounted() {
  [[ -z "$STORAGE_NODE_IP" ]] && return

  if ! grep -qs "$clientMountPath " /proc/mounts; then
    mount $STORAGE_NODE_IP:/registry $clientMountPath
    echo $(date '+%Y-%m-%d %H:%M:%S') Writting to file... >> $clientMountPath/$(hostname)
    echo $(date '+%Y-%m-%d %H:%M:%S') Successfully! >> $clientMountPath/$(hostname)
  fi
}

# Ensure the same command runs only once at a time.
runSingleton() {
  lockFile=/tmp/harborapp-$2-$3.lock
  i=0
  max=25
  while [ $i -lt $max ]; do
    mkdir $lockFile && break || {
      sleep 1
      ((i++))
    }
  done

  if [ $i -ge $max ]; then
    myPid=$$
    stalePid=`ps -df | grep "$1 $2 $3" | grep -v $myPid | grep -v grep | awk '{print $2}'`
    echo Killing stale process [pid=$stalePid].
    [ -z "$stalePid" ] || kill -9 $stalePid
    mv $lockFile $lockFile.deleteme && rm -rf $lockFile.deleteme
    mkdir $lockFile || exit 1
  fi

  "$2${3^}"
  mv $lockFile $lockFile.deleteme && rm -rf $lockFile.deleteme
}

# ======== Storage Node ======== #
nfsDockerVersion=1.2.0
serverMountPath=/data/registry

initStorage() {
  chmod 777 $serverMountPath
}

resetStorage() {
  stopStorage

  docker run -dit --name nfs-server \
    -v $serverMountPath:/registry:rw \
    -v /opt/harborapp/conf/storage/nfs/exports:/etc/exports:ro \
    --net=host \
    --privileged \
    erichough/nfs-server:$nfsDockerVersion
}

stopStorage() {
  [[ "$(docker ps -qa -f name=nfs-server)" ]] && docker rm -f nfs-server
}

checkStorage() {
  nc -zv -w5 0.0.0.0 2049 && return
  resetStorage
}

# ======== Web Node ======== #
initWeb() {
  ensureRegistryMounted
}

startWeb() {
  ensureRegistryMounted
  /opt/harbor/bin/manager.sh start docker-compose.web.yml
}

restartWeb() {
  ensureRegistryMounted
  /opt/harbor/bin/manager.sh restart docker-compose.web.yml
}

# ======== Replication Job Node ======== #
initJob() {
  ensureRegistryMounted
}

startJob() {
  ensureRegistryMounted
  /opt/harbor/bin/manager.sh start docker-compose.job.yml
}

restartJob() {
  ensureRegistryMounted
  /opt/harbor/bin/manager.sh restart docker-compose.job.yml
}

# Start executing.
me=`basename "$0"`
runSingleton $me $1 $2
