#!/bin/bash
pushd /opt/harbor/bin
. ./env.sh
CMPF=$2
usage="manager.sh [command] [docker-compose-file]"

# Return info when executing commands
run() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "Error: $1" >&2
        exit $status
    fi
    return $status
}

if [ $# -lt 2 ]
then
  echo "Error args"
  exit 1
fi

fail() {
  echo $1 >&2
  exit 1
}

retry() {
  local n=0
  local max=10
  local delay=1
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo "Command failed. Attempted $n/$max:"
        sleep $delay
      else
        fail "The command has failed after $n attempts."
      fi
    }
  done
}

setEndPoint() {
  echo "Set endpoint ${EXT_ENDPOINT}"
  sed "s#EXT_ENDPOINT=.*#EXT_ENDPOINT=${EXT_ENDPOINT}#" -i /opt/harbor/bin/harbor/common/config/adminserver/env
}

prepare() {
  setEndPoint
}

stop() {
  run /usr/local/bin/docker-compose -f $1 down -v
}

start() {
  run /usr/local/bin/docker-compose -f $1 up -d
  WAIT_MAX=10
  WAIT_TIMES=0
  READY=0
  retry [ -n "$(docker ps -qa)" ]
  CONTAINERS=`docker ps -qa`
  until [ $WAIT_TIMES -ge $WAIT_MAX ] || [ $READY -eq 1 ]
  do
    sleep 1
    let WAIT_TIMES+=1
    for C in "${CONTAINERS[@]}"
    do
      STATE=`docker inspect -f {{.State.Running}} $C`
      echo "check $C container state is $STATE"
      if [ "$STATE" == "false" ]
      then
        READY=0
        break
      fi
      READY=1
    done
  done

  # exit 1 when start timeout
  if [ $WAIT_TIMES -ge $WAIT_MAX ]
  then
    exit 1
  fi

  PORTS=`docker inspect -f '{{range $k,$v:=.HostConfig.PortBindings}}{{$k}}{{end}}' $(docker ps -q)`
  for P in ${PORTS[@]}; do
    retry nc -zv -w5 0.0.0.0 ${P%/*}
  done
}

restart() {
  stop $1
  start $1
}

reload() {
  run docker restart $1 
}

check() {
  if [ $# -lt 2 ]
  then
    echo "Missing arg..."
    exit 1
  fi  
}

echo "Check..."
check $@

echo "Prepare..."
prepare

case $1 in
    start)
    start $CMPF
    ;;
    stop)
    stop $CMPF
    ;;
    restart)
    restart $CMPF
    ;;
    reload)
    reload $2
    ;;
    *)
    echo "invaid $1 $usage"
    exit 1;;
esac

popd
exit 0

