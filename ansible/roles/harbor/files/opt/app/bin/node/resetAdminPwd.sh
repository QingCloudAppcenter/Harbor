#!/usr/bin/env bash
pwd=e3f934c188980b7cb230294f83cb2326
#example  
#password     7055c709338844684a03afd47eb99eaf (1.7.1)  901e944c153438064a68712fef73c2dd (1.9.3)  --> Harbor12345                           
#salt         7t3s93zk7qhcg7lqx1xm9meega26ryte          ne4triv6j6f5074ei7q36nbqvd1ow5pz

psql -U postgres -h localhost -d registry << EOF
  update harbor_user set password='${pwd}',salt='x9vtop1qd0cnzfg7cus8h613df1imq8f' where username='admin';
EOF
