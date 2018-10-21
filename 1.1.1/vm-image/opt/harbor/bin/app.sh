#!/usr/bin/env bash

minioVersion="RELEASE.2018-10-06T00-15-16Z"

storageInit() {
  mkdir -p /data/storage/harbor
}

storageStart() {
  docker run -d \
    --name minio \
    -e "MINIO_ACCESS_KEY=admin" \
    -e "MINIO_SECRET_KEY=password" \
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
