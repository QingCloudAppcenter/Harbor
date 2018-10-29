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
"$1${2^}"
