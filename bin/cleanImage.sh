#!/bin/bash

echo "Start to GC..."
readonly_res=`grep -A 2 "readonly:" /opt/harbor/bin/harbor/common/config/registry/config.yml | grep "enabled: false"`
if [ "$readonly_res" != "" ]
then
  echo "Not in readonly mode..."
  exit 1
else
  docker exec registry /usr/local/bin/docker-registry garbage-collect /etc/registry/config.yml
fi
echo "End to GC..."
exit 0