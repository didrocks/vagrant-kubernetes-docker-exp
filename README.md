# Vagrant image using Docker and Kubernetes

## General description

This vagrant testing VM is simulating a simple web server pushing and querying data from a SQL database. Each element is in its own docker container and kubernetes is used to orchestrate them.

We have 3 web server instances running on the vagrant machine (the vagrant machine in our simple case only provides one kubernetes node, but in a production environment, we could have installed kubernetes nodes on 3 vm, having the web server running on different machines), all connected to another unit handling the database.

If we kill any of them or if one web server crash, another one will be spawn and connected to the database itself. If the database stops, the web servers will return an error until they can reconnect to a database. A 30s timeouts for each sql request is used to ensure that if the new database gets different connection info like IP, port, a new web server instance will then be started with the updated connection info wired in. Persistence of the database data is achieved via a persistent volume, mounted in the db container, which would be a remote disk (NFS, cloud solution…) in a real world use case.

## Components

### Web server

#### Principle

I wrote a very [simple web server](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/app/src/server/server.go) in Go. This one creates the table if not present already, connect to the database (info are available through environment variables) and then wait for http requests on "/". Each request will start a transaction as we may have multiple web server running at the same time, get the number of visits (segregated by kubernetes pods id), increments it and commit.

Note that as the web server is kept simple, we fail it as soon as we can't connect to the database anymore (timeout is set to 30s). This way, the container will shut down, and we let kubernetes restarting a new one with a new connection (which may have different connection info if the db changed).

#### Building it

A simple [build script](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/app/build.sh) enables to build this server on your host. The resulting executable is *app/bin/server*.

#### Container

The [Dockerfile](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/Dockerfile) for that simple server is straightforward: taking an opensuse image, copying the built-in server and exposing port 80. Note that exposing the port is optional here as kubernetes in our setup will reexpose it anyway. It's useful for debugging though when running the container directly.

We are using when kubernetes provisioned the machine [our published image via docker hub](https://hub.docker.com/r/didrocks/docker-kub-webserver/) named *didrocks/docker-kub-webserver*.

A final note is that we copied the binary directly (and so, requiring building it on the host first) instead of building it in the container. This is to keep the container small without installing into it gcc, golang, git which won't be useful when running the server itself…

#### Kubernetes orchestration

We are running a [replication controller](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/kubernetes/webserver-rc.yaml) to keep 3 pods running all the time. Each pod will expose port 80 and we tag those pods with *app: webserver*. Note that we pass to them the database environment variables for user, password, database name that are common with the database pod.

To get a cheap load balancer and an unique and stable IP address to connect to any of those 3 pods, we are declaring a [kubernetes service](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/kubernetes/webserver-service.yaml). This one fetch the replication controller pods via the *app: webserver* tag, and redirect port 80 to port 30001. Consequently, navigating to *http://ip_of_this_service:30001/* will redirect to any of those 3 pods, on port 80.

### Database

#### Container

We are using a mysql database with the reference database docker image hosted already on docker hub: the [mysql](https://hub.docker.com/_/mysql/) image. We pass environment variable (user name, passwords, database name…) through environment variable in the [kubernetes pod description](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/kubernetes/db.yaml#L11).

#### Kubernetes orchestration

We are using here a [single db pod](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/kubernetes/db.yaml), exposing the mysql container port, mounting some persistent storage (here on host, instead of a NFS or cloud remote disk) and passing environment variables as discussed above.

Finally, we expose a stable [db service](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/kubernetes/db-service.yaml) which will enable getting a fixed internally reachable IP address passed to web server containers through their environment variables (*DB_SERVICE_SERVICE_HOST* and *DB_SERVICE_SERVICE_PORT*), see their usage [in the web service code](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/app/src/server/server.go#L68).

## Vagrant testing environment

### Provisioning

The [Vagrantfile](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/Vagrantfile) uses opensuse 13.2 as a base testing environment, forwards ports *30001* (the web server kubernetes service address exposure) to *8000* so that the host can get an access to the web servers.

A provisioning script [vagrantsetup.sh](https://github.com/didrocks/vagrant-kubernetes-docker-exp/blob/master/vagrantsetup.sh) is run the first time we start the machine. This one:
* add the opensuse virtualization repo and install kubernetes and docker.
* fix some cyclic dependencies in systemd unit as well as missing ServiceAccount keys.
* enable docker (including socket) and kubernetes systemd services so that next boot starts them up.
* start also those systemd units right away for the current initial boot.
* create the database directory on the host.
* register the kubernetes units. This will then starts the pods (and so, docker containers). Once they are registered, any machine reboot will bring them back up.

### Note on the provisioning

As the 2 containers (web server and db) are downloaded from the docker hub for this initial provisioning, this may takes some time. Waiting for a couple of minutes once provisioning is done before the system is fully ready (containers started and addresses reachable) might be necessary, depending on network and virtualized disk io conditions.

## Using it

### Starting and first request

Just `cd` into this root directory and run `vagrant up`. Provisioning will happen, once the command returned, wait for a couple of minutes (see remarks above) and head to http://localhost:8000/.

You should see something along the lines:
```
Hello from webserver-rc-m6m54!

You visited:
- webserver-rc-m6m54 1 times
```

The id corresponds to the hostname, which is set by kubernetes as the docker hostname to corresponds to the pod web server answering the request.

On refresh in the same browser session, the kubernetes service load balancer (via kube-proxy) will try to redirect those requests on the same pod (and so, the counter will just increase).

### Hitting another pod

Other browser sessions (like opening http://localhost:8000/ in a private browser mode or using another browser) will likely hit another pod. New refreshes there will thus target different pods:
```
Hello from webserver-rc-36rvq!

You visited:
- webserver-rc-m6m54 1 times
- webserver-rc-36rvq 4 times
```

If you can't hit another pod that way, refer to "Simulating one web server failure" as a way for us to kill one container and thus, hit another pod.

### Inspecting the environment

You can run `vagrant ssh` to ssh into the environment. `kubectl get pods,services` should return something like:
```
$ kubectl get pods,services
NAME                 READY     STATUS    RESTARTS   AGE
db                   1/1       Running   0          2m
webserver-rc-36rvq   1/1       Running   1          2m
webserver-rc-m6m54   1/1       Running   1          2m
webserver-rc-q86j9   1/1       Running   1          2m
NAME                CLUSTER_IP      EXTERNAL_IP   PORT(S)    SELECTOR        AGE
db-service          10.254.246.93   <none>        3306/TCP   app=db          2m
kubernetes          10.254.0.1      <none>        443/TCP    <none>          3m
webserver-service   10.254.195.30   nodes         80/TCP     app=webserver   2m
```

You can check here that the db pod is running, as well as the 3 replication controller web server ones. Then, we see the 2 services (db and web server) + the kubernetes master service.

You can as well inspect the corresponding docker containers that were provisioned:
```
$ sudo docker ps
CONTAINER ID        IMAGE                                  COMMAND                  CREATED              STATUS              PORTS               NAMES
3f28a73c8a25        didrocks/docker-kub-webserver          "/bin/sh -c /app/serv"   About a minute ago   Up About a minute                       k8s_webserver.1a7d8deb_webserver-rc-m6m54_default_7ccfe5d8-7d48-11e5-bb25-080027d9f9e5_aca9c4ed
3b71b73da7e9        didrocks/docker-kub-webserver          "/bin/sh -c /app/serv"   About a minute ago   Up About a minute                       k8s_webserver.1a7d8deb_webserver-rc-q86j9_default_7cd041fd-7d48-11e5-bb25-080027d9f9e5_715741ce
e7f34c41239d        didrocks/docker-kub-webserver          "/bin/sh -c /app/serv"   About a minute ago   Up About a minute                       k8s_webserver.1a7d8deb_webserver-rc-36rvq_default_7cd0f1d2-7d48-11e5-bb25-080027d9f9e5_3d94f546
6434025be627        mysql                                  "/entrypoint.sh mysql"   About a minute ago   Up About a minute                       k8s_db.81a7c63b_db_default_7ca61afb-7d48-11e5-bb25-080027d9f9e5_58f36843
403d8c1b474a        gcr.io/google_containers/pause:0.8.0   "/pause"                 3 minutes ago        Up 3 minutes                            k8s_POD.3ef3f8d9_webserver-rc-q86j9_default_7cd041fd-7d48-11e5-bb25-080027d9f9e5_4df1e262
2c88f251ff38        gcr.io/google_containers/pause:0.8.0   "/pause"                 3 minutes ago        Up 3 minutes                            k8s_POD.3ef3f8d9_webserver-rc-36rvq_default_7cd0f1d2-7d48-11e5-bb25-080027d9f9e5_6a4271c5
596d2bb47813        gcr.io/google_containers/pause:0.8.0   "/pause"                 3 minutes ago        Up 3 minutes                            k8s_POD.3ef3f8d9_webserver-rc-m6m54_default_7ccfe5d8-7d48-11e5-bb25-080027d9f9e5_8e7949cd
266698a441e0        gcr.io/google_containers/pause:0.8.0   "/pause"                 3 minutes ago        Up 3 minutes                            k8s_POD.9665f93d_db_default_7ca61afb-7d48-11e5-bb25-080027d9f9e5_d251a0c3
```
We can see here the 3 running container instances based on *didrocks/docker-kub-webserver* and the one based on *mysql*.

### Simulating one web server failure

We can easily simulate a failure of a web server by shutting down the docker container running it.

Run `vagrant ssh` to ssh into the testing environment. We need to know which container we are going to stop corresponding to the current hit pod. We can filter and then stop the correct container via `sudo docker ps | grep webserver-rc-m6m54 | grep kub-webserver | cut -f1 -d' ' | xargs sudo docker stop` for instance.

Hit again http://localhost:8000/ and you will get something like:
```
Hello from webserver-rc-q86j9!

You visited:
- webserver-rc-m6m54 1 times
- webserver-rc-36rvq 4 times
- webserver-rc-q86j9 1 times
```

And new refresh on the first used browser session will now hit *webserver-rc-q86j9*. Another *sudo docker ps* on the client will show that a new docker container as well for *webserver-rc-m6m54* has been restarted by kubernetes. Finally `kubectl get pods` should show up one more restart for the *webserver-rc-m6m54* pod.

### Persistence of the environment

If you `vagrant halt` and `vagrant up` again, you will see that pods and services are restarted. There is no provisioning nor docker image download in that situation and you can reach http://localhost:8000/ again, which kept its previous pods visit stats.

## Ideas for some improvements

This testing environment is just an experiment and not ready for production. A lot of aspects can be improved like:
- the real environment will have more nodes distributed across multiple machines (here, as all pods are on the same one, the replication controller is more for an illustration purpose). The persistent db disk will be on a shared network resource.
- we can have the db using some master/master or master/slave replication pods. That way, the db wouldn't be the bottleneck due to locking and loads will be distributed.
- the web server should be more resilient to failure or db timeout and retrying to connect, even if it's easy here to let one die and another to spawn. Also the database transaction lock could be more fine-grained.
- initial provisioning is using docker hub, which is a remote server and so, images can be slow to download. It happens on that initial load that the db is up after the web server containers. The consequence is that the first container instance for each web server pod will timeout after 30s and then respawn (most of the time, just once) until they have the correct environment to connect to the db.
- secrets like db password and users should be shared and hidden in a secret file (even if the db is theoretically not addressable from outside of kubernetes network).
- load balancing by kubernetes service is quite simple, we can hook up a more sophisticated external one.
- a health check system (heartbeat) on the database and web server will be great to restart dead containers (and so, pods), way quicker.
