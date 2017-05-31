# Harbor high-available Installer

This project helps users to deploy a high-available Docker Registry depending on the enterprise docker registry project [Harbar](https://github.com/vmware/harbor). If you only want to install harbor without HA,please follow the [Harbor Install Guide](https://github.com/vmware/harbor/blob/master/docs/installation_guide.md)

### Architecture
![](snapshot/WX20170517-154334@2x.png)

### High-available components

* Web services(ui, adminserver, registry)
* Registry Storage
* Database(Not implemented)

### Required

* Docker v1.10+
* Docker-Compose 1.7.1+
* OpenSSL
* Harbor-online-installer-v1.0+
* Redis
* Access to dockerhub.qingcloud.com[optional]

### Prepare for install

* `./install.ha.sh -web localhost -s allinone` install allinone mode for configuration
* `./uninstall.sh` stop instance and remove data,keep configuration
* copy ./harbor/* from src to machine ./harbor/*

### Install services by role

* Log
  ```shell
  ./install.ha.sh -s log
  ```
* MySQL
  ```shell
  ./install.ha.sh -s db -log log_host
  ```
* Redis
  ```shell
  ./install.ha.sh -s redis -log log_host
  ```
*  Job
  ```shell
  ./install.ha.sh -s job -mysql mysql_host -web web_host -log log_host
  ```
* Web (ui, adminserver, registry)
  ```shell
  ./install.ha.sh -s web -web web_host -p https -mysql mysql_host -log log_host -job job_host -redis redis_host -qs_acc [accesskey] -qs_sec [accessSecret] -qs_bucket [bucket] -qs_zone [zone] -qs_root [root]
  ```

### Install Allinone with QingStor storage

* Allinone
  ```shell
  ./install.ha.sh -s allinone -web web_host -qs_acc [accesskey] -qs_sec [accessSecret] -qs_bucket [bucket] -qs_zone [zone] -qs_root [root]
  ```
  
### Install Allinone with Volume storage

* Allinone
```shell
./install.ha.sh -s host -web web_host
```

`web_host` is your service host, IP address or domain name without protocol. This script will generate self-signed certificates for TLS. If you use own ca-certificates,please update relevant files.

### Manager

You can use `manager.sh` to start/stop/restart echo component, for example:
`./manager.sh stop docker-compose.web.yml`


### Usage

*__Note__*:

Add --insecure-registry option for Docker client in case use self-signed certificates.See [details](https://docs.docker.com/registry/insecure/).

Restart `systemctl restart docker`

###### Login

`docker login -u -p yourhub.domain.com`


###### Push&Pull

`docker push yourhub.domain.com/project/repo:tag`

`dokcer pull yourhub.domain.com/project/repo:tag`


### License
Harbor high-available Installer is available under the [Apache 2 license](LICENSE).

This project uses open source components which have additional licensing terms.  The official docker images and licensing terms for these open source components can be found at the following locations:

* Harbor:
[license](https://github.com/vmware/harbor/blob/master/LICENSE)