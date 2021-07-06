#!/usr/bin/env bash
PATCHVER='001'
command=$1
args="${@:2}"

isDev() {
  [ "$APPCTL_ENV" == "dev" ]
}

log() {
  if [ "$1" == "--debug" ]; then
    isDev || return 0
    shift
  fi
  logger -S 5000 -t appctl --id=$$ -- "[cmd=$command args='$args'] $@"
}

execute() {
  local cmd=$1; log --debug "Executing command ..."
  [ "$(type -t $cmd)" = "function" ] || cmd=_$cmd
  $cmd ${@:2}
}

BACKDIR=/data/patch$PATCHVER
patch() {
  mkdir -p $BACKDIR
  mv /opt/app/current/conf/confd/conf.d/harbor.sh.toml $BACKDIR
  mv /opt/app/current/conf/confd/templates/harbor.sh.tmpl $BACKDIR

  cp /appcenter-patch/harbor.sh.toml /opt/app/current/conf/confd/conf.d
  cp /appcenter-patch/harbor.sh.tmpl /opt/app/current/conf/confd/templates

  systemctl restart confd
}

rollback() {
  find $BACKDIR -name harbor.sh.toml -exec cp {} /opt/app/current/conf/confd/conf.d \;
  find $BACKDIR -name harbor.sh.tmpl -exec cp {} /opt/app/current/conf/confd/templates \;

  systemctl restart confd
}

isDev && set -x
set -eo pipefail
execute $command $args