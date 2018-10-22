#!/usr/bin/env bash

source /opt/harbor/bin/env.sh
minioVersion="RELEASE.2018-10-06T00-15-16Z"

[[ "$NODE_ROLE" == "$1_node" ]] || exit 0

genTokenWithLength() {
  < /dev/urandom tr -dc A-Za-z0-9 | head -c${1:-$1}
}

storageGenerateToken() {
  accessKey=$(genTokenWithLength 21)
  secretKey=$(genTokenWithLength 41)

  cat << EOF
{"accessKey":"$accessKey","secretKey":"$secretKey"}
EOF
}

storageStart() {
  mkdir -p /data/storage/harbor

  docker run -d \
    --name minio \
    -e "MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY" \
    -e "MINIO_SECRET_KEY=$MINIO_SECRET_KEY" \
    -v /data/storage:/data \
    -p 80:9000 \
    --restart always \
    minio/minio:${minioVersion} server /data
}

storageStop() {
  if [ "$(docker ps -q -a -f name=minio)" ]; then
    docker rm -f minio
  fi
}

storageRestart() {
  storageStop
  storageStart
}

"$1${2^}"
