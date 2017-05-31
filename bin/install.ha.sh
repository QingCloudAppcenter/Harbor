#!/bin/bash
set +e
set -o noglob
bold=$(tput bold)
underline=$(tput sgr 0 1)
reset=$(tput sgr0)
red=$(tput setaf 1)
green=$(tput setaf 76)
white=$(tput setaf 7)
tan=$(tput setaf 202)
blue=$(tput setaf 25)
underline() { printf "${underline}${bold}%s${reset}\n" "$@"
}
h1() { printf "\n${underline}${bold}${blue}%s${reset}\n" "$@"
}
h2() { printf "\n${underline}${bold}${white}%s${reset}\n" "$@"
}
debug() { printf "${white}%s${reset}\n" "$@"
}
info() { printf "${white}➜ %s${reset}\n" "$@"
}
success() { printf "${green}✔ %s${reset}\n" "$@"
}
error() { printf "${red}✖ %s${reset}\n" "$@"
}
warn() { printf "${tan}➜ %s${reset}\n" "$@"
}
bold() { printf "${bold}%s${reset}\n" "$@"
}
note() { printf "\n${underline}${bold}${blue}Note:${reset} ${blue}%s${reset}\n" "$@"
}
set -e
set +o noglob

usage=$" 
Usage:

./install.sh -s service -p protocol -web web_host -mysql mysql_host -log log_host -job job_host

-s     service     [allinone|db|job|log|web|redis] service will be installed.
-web   web_host    The web service's host.
-p     protocol    http or https for web service,default is https.
-qs_acc acckey    QingStor API Access
-qs_sec secret    QingStor API Secret
-qs_bucket bucket QingStor Bucket
-qs_zone  zone    QingStor Zone
-qs_root  root    QingStor bucket root direcotry
-redis redist_host Redis for registry cache
-mysql  mysql_host     The database's host.
-log log_host    The rsyslog's host.
-job job_host    The replication's host.

"

protocol=http
web_host=127.0.0.1
job_verify_remote=false
mysql_host=127.0.0.1
log_host=127.0.0.1
job_host=127.0.0.1
redis_host=127.0.0.1
qs_acc="qs_acc"
qs_sec="qs_sec"
qs_zone="qs_zone"
qs_root="qs_root"
service=allinone

harbor_download_url=https://github.com/vmware/harbor/releases/download/v1.1.1/harbor-online-installer-v1.1.1.tgz
harbor_dir=./harbor
dst_cert_dir=/data/cert
src_cert_dir=${harbor_dir}/cert

ui_port=4000
admin_port=6000
job_port=7000

item=0

while [ $# -gt 0 ]; do
        case $1 in
            -s)
            service=$2
            shift
            ;;
            -web)
            web_host=$2
            shift
            ;;
            -p)
            protocol=$2
            shift
            ;;
            -mysql)
            mysql_host=$2
            shift
            ;;
            -log)
            log_host=$2
            shift
            ;;
            -job)
            job_host=$2
            shift
            ;;
            -redis)
            redis_host=$2
            shift
            ;;
            -qs_acc)
            qs_acc=$2
            shift
            ;;
            -qs_sec)
            qs_sec=$2
            shift
            ;;
            -qs_bucket)
            qs_bucket=$2
            shift
            ;;
            -qs_root)
            qs_root=$2
            shift
            ;;
            -qs_zone)
            qs_zone=$2
            shift
            ;;
            *)
            info "invaid $1 $usage"
            exit 1;;
        esac
        shift || true
done

# common funcs
function check_docker {
	if ! docker --version &> /dev/null
	then
		error "Need to install docker(1.10.0+) first and run this script again."
		exit 1
	fi

	# docker has been installed and check its version
	if [[ $(docker --version) =~ (([0-9]+).([0-9]+).([0-9]+)) ]]
	then
		docker_version=${BASH_REMATCH[1]}
		docker_version_part1=${BASH_REMATCH[2]}
		docker_version_part2=${BASH_REMATCH[3]}

		# the version of docker does not meet the requirement
		if [ "$docker_version_part1" -lt 1 ] || ([ "$docker_version_part1" -eq 1 ] && [ "$docker_version_part2" -lt 10 ])
		then
			error "Need to upgrade docker package to 1.10.0+."
			exit 1
		else
			note "docker version: $docker_version"
		fi
	else
		error "Failed to parse docker version."
		exit 1
	fi
}

function check_dockercompose {
	if ! docker-compose --version &> /dev/null
	then
		error "Need to install docker-compose(1.7.1+) by yourself first and run this script again."
		exit 1
	fi

	# docker-compose has been installed, check its version
	if [[ $(docker-compose --version) =~ (([0-9]+).([0-9]+).([0-9]+)) ]]
	then
		docker_compose_version=${BASH_REMATCH[1]}
		docker_compose_version_part1=${BASH_REMATCH[2]}
		docker_compose_version_part2=${BASH_REMATCH[3]}

		# the version of docker-compose does not meet the requirement
		if [ "$docker_compose_version_part1" -lt 1 ] || ([ "$docker_compose_version_part1" -eq 1 ] && [ "$docker_compose_version_part2" -lt 6 ])
		then
			error "Need to upgrade docker-compose package to 1.7.1+."
      exit 1
		else
			note "docker-compose version: $docker_compose_version"
		fi
	else
		error "Failed to parse docker-compose version."
		exit 1
	fi
}

function check_env {
  check_docker
  check_dockercompose
  
  archiveFile="${harbor_download_url##*/}"
  
  if [ -e $archiveFile ]
  then 
    tar zxvf $archiveFile
  elif [ ! -d "${harbor_dir}" ]
  then
    echo "dowalond from ${harbor_download_url}"
    if ! (wget ${harbor_download_url} -O - | tar zxv)
    then
      exit 1
    fi
  fi
    
  if [ ! -d "${harbor_dir}/common" ]
  then
    error "Can't find ${harbor_dir}/common direcotry."
    exit 1
  fi
  if [ ! -e "${harbor_dir}/harbor.cfg" ]
  then
    error "Can't find ${harbor_dir}/harbor.cfg file."
    exit 1
  fi
  
  if [ ! -e "docker-compose.${service}.yml" ]
  then
    error "Can't find docker-compose.${service}.yml file."
    exit 1
  fi
}

function generateSelfCert {
  sub="/C=CN/ST=BJ/L=BJ/O=QC/CN=$1"
  openssl req -newkey rsa:4096 -nodes -sha256 \
  -subj $sub \
  -keyout $2/ca.key -x509 -days 365 -out $2/ca.crt
  openssl req -newkey rsa:4096 -nodes -sha256 \
  -subj $sub \
  -keyout $2/server.key -out $2/server.csr
  
  if [[ $1 =~ (([0-9]+).([0-9]+).([0-9]+).([0-9]+)) ]]
  then
    echo subjectAltName = IP:$1 > $2/extfile.cnf
    openssl x509 -req -days 365 -in $2/server.csr -CA $2/ca.crt -CAkey $2/ca.key -CAcreateserial -extfile $2/extfile.cnf -out $2/server.crt
    rm -fr $2/extfile.cnf
  else
     openssl x509 -req -days 365 -in $2/server.csr -CA $2/ca.crt -CAkey $2/ca.key -CAcreateserial -out $2/server.crt
  fi
}
    
function copyCert {
  echo "Copy from $1 to $2..."
  mkdir -p $2
  cp -fr $1/server.crt $2/server.crt
  cp -fr $1/server.key $2/server.key
}

function set_host_netmode {
  # ui
  grep -qxF "ADMIN_SERVER_URL=http://adminserver:$admin_port" ${harbor_dir}/common/config/ui/env || echo -e "ADMIN_SERVER_URL=http://adminserver:$admin_port" >> ${harbor_dir}/common/config/ui/env
  sed -i "s/httpport[[:space:]]*=[[:space:]]*[0-9]*/httpport = $ui_port/g" ${harbor_dir}/common/config/ui/app.conf
  # admin
  grep -qxF "PORT=$admin_port" ${harbor_dir}/common/config/adminserver/env || echo -e "PORT=$admin_port" >> ${harbor_dir}/common/config/adminserver/env
  # job
  grep -qxF "ADMIN_SERVER_URL=http://adminserver:$admin_port" ${harbor_dir}/common/config/jobservice/env || echo -e "ADMIN_SERVER_URL=http://adminserver:$admin_port" >> ${harbor_dir}/common/config/jobservice/env
  sed -i "s/httpport[[:space:]]*=[[:space:]]*[0-9]*/httpport = $job_port/g" ${harbor_dir}/common/config/jobservice/app.conf
  # nginx
  sed -i "s/server[[:space:]]\+ui:80;/server ui:$ui_port;/g" ${harbor_dir}/common/config/nginx/nginx.conf  
}

function add_redis_to_web {
  echo -e "SessionProvider = redis" >> ${harbor_dir}/common/config/ui/app.conf
  echo -e "SessionProviderConfig = redis:6379" >> ${harbor_dir}/common/config/ui/app.conf
}

function add_hosts {
  if grep -qxF "# Hosts for Harbor" /etc/hosts
  then
    sudo sed -i "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) ui/127.0.0.1 ui/g" /etc/hosts
    sudo sed -i "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) registry/127.0.0.1 registry/g" /etc/hosts
    sudo sed -i "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) adminserver/127.0.0.1 adminserver/g" /etc/hosts
    sudo sed -i "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) jobservice/127.0.0.1 jobservice/g" /etc/hosts
    sudo sed -i "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) job/${job_host} job/g" /etc/hosts
    sudo sed -i "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) mysql/${mysql_host} mysql/g" /etc/hosts
    sudo sed -i "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) log/${log_host} log/g" /etc/hosts
    sudo sed -i "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) redis/${redis_host} redis/g" /etc/hosts
  else
    sudo echo -e "# Hosts for Harbor\n127.0.0.1 ui\n127.0.0.1 registry\n127.0.0.1 adminserver\n127.0.0.1 jobservice\n${job_host} job\n${mysql_host} mysql\n${log_host} log\n${redis_host} redis\n" >> /etc/hosts
  fi
}

function stop_instances {
  if [ -n "$(docker-compose -f docker-compose.allinone.yml ps -q)" ]
  then
    note "stopping existing Harbor instance ..." 
    docker-compose -f docker-compose.allinone.yml down -v
  fi
  
  if [ -n "$(docker-compose -f docker-compose.${service}.yml ps -q)" ]
  then
    note "stopping existing Harbor instance ..." 
    docker-compose -f docker-compose.${service}.yml down -v
  fi
}

function start_instances {
  if [ ! -e "docker-compose.${service}.yml" ]
  then
    error "Can't find 'docker-compose.${service}.yml' direcotry."
    exit 1
  fi
  echo "start 'docker-compose.${service}.yml' services."
  docker-compose -f docker-compose.${service}.yml up -d
}

function load_images {
  if [ -f harbor*.tar.gz ]; then
  	docker load -i ${harbor_dir}/harbor*.tar.gz
  fi
  echo ""
}

function configure_redis {
  echo "redis:
    addr: redis:6379
    pool:
      maxidle: 16
      maxactive: 64
      idletimeout: 300s
    dialtimeout: 10ms
    readtimeout: 10ms
    writetimeout: 10ms" >> ${harbor_dir}/common/config/registry/config.yml
  sed -i 's#      layerinfo:[[:space:]]*[a-z]*#      layerinfo: redis#g' ${harbor_dir}/common/config/registry/config.yml
  sed -i 's#      blobdescriptor:[[:space:]]*[a-z]*#      blobdescriptor: redis#g' ${harbor_dir}/common/config/registry/config.yml
}

function configure_qingstor {
  sed -i "s/rootdirectory:/#rootdirectory:/g;s/filesystem:/#filesystem:/g" ${harbor_dir}/common/config/registry/config.yml
  sed -i "s#storage:#\
\nstorage:\
\n    qs:\
\n        accesskey: ${qs_acc}\
\n        secretkey: ${qs_sec}\
\n        bucket: ${qs_bucket}\
\n        zone: ${qs_zone}\
\n        rootdirectory: ${qs_root}#g" ${harbor_dir}/common/config/registry/config.yml
}

function prepare {
  if [ -n "$web_host" ]
  then
  	sed "s/^hostname = .*/hostname = $web_host/g" -i ${harbor_dir}/harbor.cfg
  fi
  if [ -n "$protocol" ]
  then
    sed "s/^ui_url_protocol = .*/ui_url_protocol = $protocol/g" -i ${harbor_dir}/harbor.cfg
  fi
  
  if [ "$job_verify_remote" == "false" ]
  then
    sed "s/^verify_remote_cert = on/verify_remote_cert = off/g" -i ${harbor_dir}/harbor.cfg
  fi
  
  ${harbor_dir}/prepare
  
  if [ "$service" == "web" ] || [ "$service" == "allinone" ] || [ "$service" == "host" ]
  then
    echo "generate certificates to ${dst_cert_dir}..."
    mkdir -p $src_cert_dir
    mkdir -p $dst_cert_dir
    generateSelfCert $web_host $src_cert_dir
    copyCert $src_cert_dir $dst_cert_dir
    copyCert $src_cert_dir ${harbor_dir}/common/config/nginx/cert
  fi
  
  if ! grep -qxF "redis:" ${harbor_dir}/common/config/registry/config.yml && [ "$service" != "host" ]
  then
    echo "configure redis..."
    configure_redis
    add_redis_to_web
  fi
  
  if ! grep -qxF "qs:" ${harbor_dir}/common/config/registry/config.yml && [ "$qs_acc" != "qs_acc" ]
  then
    echo "configure QingStor..."
    configure_qingstor
  fi
  
}

# -------- Main Start

h2 "[Step $item]: Check environment ..."; let item+=1
check_env

h2 "[Step $item]: Loading Harbor images ..."; let item+=1
load_images

h2 "[Step $item]: Stop existing instance of Harbor ..."; let item+=1
stop_instances

h2 "[Step $item]: Preparing environment ...";  let item+=1
prepare

h2 "[Step $item]: Set host network mode ...";  let item+=1
set_host_netmode

h2 "[Step $item]: Add hosts ...";  let item+=1
add_hosts

h2 "[Step $item]: Start instance of Harbor ..."; let item+=1
start_instances

success $"----Harbor has been installed and started successfully.----

Now you should be able to visit the admin portal at ${protocol}://${web_host}. 
For more details, please visit https://github.com/vmware/harbor .
"
exit 0
