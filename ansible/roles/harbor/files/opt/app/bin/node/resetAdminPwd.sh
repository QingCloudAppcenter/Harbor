#!/usr/bin/env bash

#example  
#password     7055c709338844684a03afd47eb99eaf (1.7.1)  901e944c153438064a68712fef73c2dd (1.9.3)  --> Harbor12345                           
#salt         7t3s93zk7qhcg7lqx1xm9meega26ryte          ne4triv6j6f5074ei7q36nbqvd1ow5pz

psql -U postgres -h localhost -d registry << EOF
  update harbor_user set password='da5e5b590fee83a718cba5dba15bce8e',salt='1vakkec1metjdyf58i93hbbbsjhw2b4g',password_version='sha256' where username='admin';
EOF
