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

./uninstall.sh

"

# 
service=allinone
remove_all=false

while [ $# -gt 0 ]; do
        case $1 in
            all)
            remove_all=true
            shift
            ;;
            *)
            info "invaid $1 $usage"
            exit 1;;
        esac
        shift || true
done

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

function remove_data {
  rm -fr /data
  rm -fr /var/log/harbor
  rm -fr ./harbor
}

function remove_hosts {
  if grep -qxF "# Hosts for Harbor" /etc/hosts
  then
    sudo sed -i -r "s/# Hosts for Harbor//g" /etc/hosts
    sudo sed -i -r "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) ui//g" /etc/hosts
    sudo sed -i -r "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) registry//g" /etc/hosts
    sudo sed -i -r "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) adminserver//g" /etc/hosts
    sudo sed -i -r "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) jobservice//g" /etc/hosts
    sudo sed -i -r "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) mysql//g" /etc/hosts
    sudo sed -i -r "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) log//g" /etc/hosts
    sudo sed -i -r "s/([0-9]+).([0-9]+).([0-9]+).([0-9]+) redis//g" /etc/hosts
  fi
    
}
item=0
h2 "[Step $item]: Stop instances ..."; let item+=1
stop_instances
if $remove_all
then
  h2 "[Step $item]: Remove data ..."; let item+=1
  remove_data
fi
h2 "[Step $item]: Remove hosts ..."; let item+=1
remove_hosts

success $"----Harbor has been uninstalled. ----"
exit 0
