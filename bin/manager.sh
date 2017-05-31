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

