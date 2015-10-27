#!/usr/bin/env bash

set -e

# add kubernetes opensuse team repo
zypper --non-interactive addrepo -Gf http://download.opensuse.org/repositories/Virtualization:containers/openSUSE_13.2/Virtualization:containers.repo
zypper --non-interactive install kubernetes-master kubernetes-node etcd docker

# there is a systemd unit dependency order issue between etcd and kubernetes api server in this repo
# etcd is After=multi-user.target but WantedBy=multi-user.target
# kube-apiserver is: After=etcd.service but WantedBy=multi-user.target
# systemd choose to not start kube-apiserver to resolve this loop. We remote the After=multi-user.target in etcd
# (which doesn't makes sense for a wanted by)
sed 's/After=multi-user.target//' /usr/lib/systemd/system/etcd.service > /etc/systemd/system/etcd.service

# create ServiceAccount adminission controller keys missing when setting up kubernetes packages
# https://github.com/kubernetes/kubernetes/issues/11355#issuecomment-127378691
ssl_keyfile=/etc/kubernetes/serviceaccount.key
openssl genrsa -out $ssl_keyfile 2048
echo "KUBE_API_ARGS='--service_account_key_file=$ssl_keyfile'" >> /etc/kubernetes/apiserver
echo "KUBE_CONTROLLER_MANAGER_ARGS='--service_account_private_key_file=$ssl_keyfile'" >> /etc/kubernetes/controller-manager

# we enable docker socket activation and kubernetes services, including local kublet
services_to_autostart="docker.socket etcd kubelet kube-apiserver kube-scheduler kube-proxy kube-controller-manager"
for service in $services_to_autostart; do
    # we enable for reboot (activated via multi-users.target)
    systemctl enable $service
    # we start them to not have to reboot right away
    systemctl start $service
done

# create storage for db data to be persistent
# in a real world usage, we would use a nfs or cloud volume so that more than
# one pod can access it, and so, we can relocate the pod.
mkdir /dbdata

# now, starts the pods and services
kubunits="db.yaml db-service.yaml webserver-rc.yaml webserver-service.yaml"
for kubunit in $kubunits; do
    kubectl create -f /vagrant/kubernetes/$kubunit
done

echo "Containers are starting to provision (db and webserver). This may takes somem minutes. Then, head over to http://localhost:8000/"
