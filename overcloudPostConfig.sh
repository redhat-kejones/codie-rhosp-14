#!/usr/bin/bash

#Parameters
user=operator
password=p@ssw0rd
email=operator@redhat.com
tenant=operators
externalNetwork=public
externalCidr=192.168.0.0/23
externalVlanId=1
externalGateway=192.168.0.1
externalDns=192.168.0.4
externalFipStart=192.168.1.70
externalFipEnd=192.168.1.199
tenantNetwork=private
tenantCidr='172.16.0.0/24'
keypairName=operator
keypairPubkey="..."

unset OS_PROJECT_NAME
unset OS_TENANT_NAME

#Start as the admin user
source /home/stack/overcloudrc

#Create the operators tenant and operator user defined above
openstack project create $tenant --description "Project intended for shared resources and testing by Operators" --enable
openstack quota set --ram 262144 --instances 20 --cores 80 --gigabytes 1000 --volumes 40 $tenant
openstack user create $user --project $tenant --password $password --email $email --enable

#Grant the admin role to the operator admin
openstack role add admin --user $user --project $tenant

#create an rc file for the new operator user
cp /home/stack/overcloudrc /home/stack/${user}rc
sed -i "s/\(OS_USERNAME=\).*/\1${user}/" /home/stack/${user}rc
sed -i "s/\(OS_TENANT_NAME=\).*/\1${tenant}/" /home/stack/${user}rc
sed -i "s/\(OS_PROJECT_NAME=\).*/\1${tenant}/" /home/stack/${user}rc
sed -i "s/\(OS_PASSWORD=\).*/\1${password}/" /home/stack/${user}rc

#Switch to the new operator
source /home/stack/${user}rc

#Add ICMP and SSH incoming rules to the default security group in operators tenant
openstack security group rule create --protocol icmp $(openstack security group list --project operators -c ID -f value)
openstack security group rule create --protocol tcp $(openstack security group list --project operators -c ID -f value)
openstack security group rule create --protocol udp $(openstack security group list --project operators -c ID -f value)

#Create a temp public key file
echo $keypairPubkey > /tmp/${keypairName}.pub
#Import the public key for the operator user
openstack keypair create --public-key /tmp/${keypairName}.pub $keypairName

#Create a base flavor for use later
openstack flavor create --id 1 --ram 256 --disk 1 --vcpus 1 --public m1.tiny
openstack flavor create --id 2 --ram 1024 --disk 10 --vcpus 1 --public m1.small
openstack flavor create --id 3 --ram 2048 --disk 20 --vcpus 2 --public m1.medium
openstack flavor create --id 4 --ram 4096 --disk 40 --vcpus 4 --public m1.large
openstack flavor create --id 5 --ram 8192 --disk 80 --vcpus 8 --public m1.xlarge
openstack flavor create --id 6 --ram 12288 --disk 80 --vcpus 4 --public cf.min
openstack flavor create --id 7 --ram 16384 --disk 80 --vcpus 8 --public ocp1.master
openstack flavor create --id 8 --ram 32768 --disk 80 --vcpus 8 --public ocp1.node
openstack flavor create --id 9 --ram 12288 --disk 80 --vcpus 4 --public sat6.min

#TODO: Need to figure out a way to make this dynamic on whether flat or vlan
#Create shared external network via flat provider type

#External is VLAN
#openstack network create --provider-network-type vlan --provider-physical-network datacentre --provider-segment $externalVlanId --share --external $externalNetwork

#External is Flat
openstack network create --provider-network-type flat --provider-physical-network datacentre --share --external $externalNetwork

#Create external subnet
neutron subnet-create $externalNetwork $externalCidr --name ${externalNetwork}-sub --disable-dhcp --allocation-pool=start=$externalFipStart,end=$externalFipEnd --gateway=$externalGateway --dns-nameserver $externalDns

#Create a private tenant vxlan network
openstack network create $tenantNetwork

#Create private tenant subnet
neutron subnet-create $tenantNetwork $tenantCidr --name ${tenantNetwork}-sub --dns-nameserver $externalDns

#Create provider networks
#Provisioning
neutron net-create provisioning --provider:network_type flat  --provider:physical_network prov
neutron subnet-create provisioning 192.168.2.0/24 --name provisioning-sub --allocation-pool=start=192.168.2.70,end=192.168.2.99 --no-gateway

#Create a router
neutron router-create router-$externalNetwork
#Add an interface on the router for the tenant network
neutron router-interface-add router-$externalNetwork ${tenantNetwork}-sub
#Set the external gateway on the new router
neutron router-gateway-set router-$externalNetwork $externalNetwork
