# HPC on Azure Kubernetes Service

## Pre-requisites

This installation assumes you have the following setup:

* Docker installed to build the containers
* AKS cluster with Infiniband feature flag enabled

  To enable the feature run:
  ```
  az feature register --name AKSInfinibandSupport --namespace Microsoft.ContainerService
  ```

  Check the status with the following:
  ```
  az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/AKSInfinibandSupport')].{Name:name,State:properties.state}"
  ```

  Register when ready:

  ```
  az provider register --namespace Microsoft.ContainerService
  ```

## Deploy

All the instructions here will be using environment variables for the parameters.  Below are the environment variables that have been used to test using WSL2 - you may need to set up ssh keys if you do not have them already.

```
resource_group=hpc-on-aks-demo
aks_admin_user=$USER
aks_public_key="$(</home/$USER/.ssh/id_rsa.pub)"
```

First create a resource group to deploy in to:

```
az group create --location westeurope --name $resource_group
```

Next, deploy the `azureDeploy.bicep` template.  This is using my current user with the my ssh key in `.ssh`:

```
az deployment group create \
    --resource-group $resource_group \
    --template-file azureDeploy.bicep \
    --parameters \
        aksAdminUsername=$aks_admin_user \
        aksPublicKey="$aks_public_key" \
    | tee deploy-output.json
```

> Note: the output is also written to `deploy-output.json` which is used in later code snippets to get resource names.

First we will need the AKS cluster name.  This is an output from the deployment but it is also available from the portal.

```
aks_cluster_name=$(jq -r .properties.outputs.aksClusterName.value deploy-output.json)
```

> Note: if you do not have `jq` installed you can just look in the json output from the deployment.

Now to set up the credentials for `kubectl`:

```
az aks get-credentials --overwrite-existing --resource-group $resource_group --name $aks_cluster_name
```

## Installing the Mellanox driver on the host

These steps require the ACR name.  This is in the output from the deployment:

```
export acr_name=$(jq -r .properties.outputs.acrName.value deploy-output.json)
```

Note: `acr_name` is exported so that it can be used by `render_template.py` later.

Log in to the ACR using the Azure CLI:

```
az acr login -n $acr_name
```

The host image provided by AKS does not contain the Mellanox driver at the time of writing.  However, the AKS team have a GitHub project, [aks-rdma-infiniband](https://github.com/Azure/aks-rdma-infiniband), to enable this through a daemonset.  Full details can be seen in the GitHub project but the steps are outline below.

> Note: these steps require Docker to build the container.

Pull the repo from GitHub:

```
git clone https://github.com/Azure/aks-rdma-infiniband.git
```

Build and push the container:
```
cd aks-rdma-infiniband
docker build -t ${acr_name}.azurecr.io/mlnx-driver-install .
docker push ${acr_name}.azurecr.io/mlnx-driver-install
```

Update the container name and deploy the daemonset:
```
sed -i "s/<insert image name here>/${acr_name}.azurecr.io\/mlnx-driver-install:latest/g" shared-hca-images/driver-installation.yml
kubectl apply -k shared-hca-images/.
```

To check the installation:
```
kubectl get pods
kubectl logs <name of installation pod>
```

## Containers

The containers have created based on the scripting from [azhpc-images](https://github.com/Azure/azhpc-images) GitHub repo.  However, it has been separated into the following hierarchy:
* __Base container__: Contains the OS, Mellanox OFED driver and general tools.
* __MPI container__: Adding an MPI version to the base container.
* __Application container__: New container created for each application. 

The Azure images for VMs contain all the different MPIs doing this significantly increases the size which is particularly noticeable for containers.

![Container Hierarchy](images/container-hierarchy.png)

### Building the containers

#### Ubuntu 20.04 container with Mellanox OFED - ubuntu2004-mofed
```
pushd containers/ubuntu2004-mofed-docker
docker build -t ${acr_name}.azurecr.io/ubuntu2004-mofed .
docker push ${acr_name}.azurecr.io/ubuntu2004-mofed
popd
```

#### HPCX MPI layer on top of the previous container image - ubuntu2004-mofed-hpcx
```
pushd containers/ubuntu2004-mofed-hpcx-docker
docker build --build-arg ACR_NAME=${acr_name} -t ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx .
docker push ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx
popd
```

#### OpenFoam v10 container - ubuntu2004-mofed-hpcx-openfoam
```
pushd containers/ubuntu2004-mofed-hpcx-openfoam-docker
docker build --build-arg ACR_NAME=${acr_name} -t ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx-openfoam .
docker push ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx-openfoam
popd
```
#### Devito container - ubuntu2004-mofed-hpcx-devito
```
pushd containers/ubuntu2004-mofed-hpcx-devito-docker
docker build --build-arg ACR_NAME=${acr_name} -t ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx-devito .
docker push ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx-devito
popd
```

## Testing IB with IMB-MPI PingPong

An example, `pingpong-mpi-job.yaml.template`, is provided to run the IMB-MPI1 PingPong test.  It is parameterized on the ACR name and so the YAML can be created as follows:

```
sed "s/__ACRNAME__/${acr_name}/g" examples/pingpong-mpi-job.yaml.template > examples/pingpong-mpi-job.yaml
```

This example uses an `indexed-job` to run the MPI test.  All the initialization and start-up is embedded in the command.  The pods will all terminate once the job is complete although the storage remains.  The `index` is used to find the first pod and this will create the home directory, ssh keys, hostfile and launch `mpirun`.  Here is an overview of steps:

* Start SSH daemon
* Touch file `/home/hosts/<IP-ADDRESS>`
* Add user and group
* If index == 0:
  - Create home directory
  - Create SSH key and set SSH config and authorized_keys
  - Wait for all hosts to start by checking the number of files in /home/hosts
  - Create a hostfile from the filenames in /home/hosts
  - Launch `mpirun` command
  - Get exit status and create file `/home/complete` with either success or failure
* Else index > 0:
  - Wait for file `/home/complete` to be created
* Exit pod

Deploy with:

```
kubectl apply -f examples/pingpong-mpi-job.yaml
```

The mpirun output will be in the first pod.  You can find this with:

```
kubectl get pods
```

And, then look at the `indexed-job-0-XXXXX`:

```
kubectl logs indexed-job-0-XXXXX
```

This is example output:

```
...
#---------------------------------------------------
# Benchmarking PingPong
# #processes = 2
#---------------------------------------------------
       #bytes #repetitions      t[usec]   Mbytes/sec
            0         1000         1.68         0.00
            1         1000         1.68         0.59
            2         1000         1.68         1.19
            4         1000         1.69         2.36
            8         1000         1.69         4.73
           16         1000         1.69         9.45
           32         1000         1.88        17.02
           64         1000         1.98        32.36
          128         1000         2.02        63.25
          256         1000         2.60        98.30
          512         1000         2.73       187.41
         1024         1000         2.77       369.03
         2048         1000         3.10       660.86
         4096         1000         3.75      1091.99
         8192         1000         4.27      1919.30
        16384         1000         5.53      2962.70
        32768         1000         7.60      4309.94
        65536          640        10.86      6032.44
       131072          320        16.94      7736.39
       262144          160        19.57     13395.44
       524288           80        30.64     17113.45
      1048576           40        53.36     19650.28
      2097152           20        98.84     21218.09
      4194304           10       181.01     23172.19
```

## Launching with Helm

Helm can simplify deploying on k8s.  A deployment with helm is called a "chart" and the folder structure is as follows:

* `chart.yaml`: Metadata about what is deployed
* `values.yaml`: Values that can be substituted into the k8s yaml files
* `templates`: directory containing yaml files to be deployed

All the yaml files will be preprocessed and values will be substituted in.  Helm will manage deploying or clearing up all the resources for a chart and multiple instances of a chart can be deployed.

### The AzureFile CSI NFS storageclass

The helm examples in this repository use the `azurefile-csi-nfs-storageclass`.  This should be installed with the following command:

```
kubectl apply -f azurefile-csi-nfs-storageclass.yaml
```

### Running the IMB-MPI1 Allreduce Helm Chart

An example is provided for IMB-MPI1 Allreduce jobs and can be run as follows:

```
helm install allreduce examples/imbmpi-allreduce-job \
  --set procsPerNode=120,numberOfNodes=2,acrName=${acr_name}
```

The helm charts that are deployed can be seen with `helm list`:

```
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                           APP VERSIONallreduce       default         1               2022-11-03 11:51:27.455113109 +0000 UTC deployed        imbmpi-allreduce-job-0.1.0      0.1.0
```

The same `kubectl` commands as before can be used to see the pods that are created and viewing the logs.

We can remove the job and clear up all the resources with `helm uninstall`:

```
helm uninstall allreduce
```

## Schedulers

Kubernetes allows you to change the scheduler and examples are provided for some alternatives.  The default scheduler with Kubernetes is not designed for the types of jobs we are running.

### Breaking the default scheduler

The default scheduler does not gang-schedule pods for a job.  Therefore jobs can deadlock when nodes are constrained.  We can create this situation fairly quickly by setting the nodepool size to 4 and submitting many 4 node jobs, e.g.

```
for n in $(seq -w 1 20); do 
  helm install allreduce-${n} examples/imbmpi-allreduce-job \
    --set numberOfNodes=4,acrName=${acr_name}
done
```

At some point it is likely to enter the state where multiple jobs are starting but none of them can progress as they cannot get all the required resources.

All helm jobs can be uninstalled with the following command:

```
helm list --short | xargs helm uninstall
```

> The helm jobs can be filted with `grep`. 

### Volcano scheduler

Website: https://volcano.sh/

This is designed for high-performance batch computing and provides more efficient scheduling and supports many different scheduling algorithms.  It also includes support for launching MPI jobs.  Volcano adds a new resource type called `VolcanoJob`.  This new job launches MPI by creating an additional pod to run `mpirun`.

#### Installation

The following commands will install volcano using Helm:

```
git clone https://github.com/volcano-sh/volcano.git
cd volcano
kubectl create namespace volcano-system
helm install volcano installer/helm/chart/volcano --namespace volcano-system
```

#### Running the IMB-MPI1 PingPong example

An example is provided.  First update the Azure Container Registry in the YAML file:

```
sed "s/__ACRNAME__/${acr_name}/g" \
  examples/pingpong-mpi-job-volcano.yaml.template \
  > examples/pingpong-mpi-job-volcano.yaml
```

Listing the pods will show the `mpimaster` and `mpiworker`s:

```
lm-mpi-job-mpimaster-0     0/1     Completed     0          34s
lm-mpi-job-mpiworker-0     1/1     Terminating   0          34s
lm-mpi-job-mpiworker-1     1/1     Terminating   0          34s
```

The MPI output can be viewed from the `mpimaster` log:

```
kubectl logs lm-mpi-job-mpimaster-0
```

#### Uninstalling

Volcano can be uninstalled by running the following:

```
helm uninstall --namespace volcano-system volcano
kubectl delete namespace volcano-system
```

### YuniKorn scheduler

Website: https://yunikorn.apache.org/

YuniKorn is an Apache project.  There is an option to use this as the default scheduler with the `--set enableSchedulerPlugin=true`.

#### Installation

```
helm repo add yunikorn https://apache.github.io/yunikorn-release
helm repo update
kubectl create namespace yunikorn
helm install yunikorn yunikorn/yunikorn --namespace yunikorn --set enableSchedulerPlugin=true
```

#### Running the IMB-MPI1 Allreduce example

A helm chart is provided for this.  It can be lauched as follows:

```
helm install allreduce-yk examples/imbmpi-allreduce-job-yunikorn \
    --set numberOfNodes=2,acrName=${acr_name}
```

Multiple jobs can be launched and they will be scheduled correctly without deadlocking:

```
for n in $(seq -w 1 10); do 
  helm install allreduce-${n} examples/imbmpi-allreduce-job-yunikorn \
    --set numberOfNodes=4,acrName=${acr_name}
done
```

#### Uninstalling

YuniKorn can be uninstalled by running the following:

```
helm uninstall --namespace yunikorn yunikorn
```


## Run the OpenFoam Using Helm and YuniKorn

To run the OpenFoam demo, please make sure you have installed helm version 3 on your device.

The file `examples/openfoam-job-yunikorn/values.yaml` containes the job parameters which can be adjusted or overridden:

```
# Openfoam Job parameters
userName: hpcuser
userId: 10000
groupName: hpcuser
groupId: 10000
procsPerNode: 120
numberOfNodes: 2
acrName: 
```

To run the OpenFoam job 
```
# helm install <release-name> <chart> --set <name>=<value>,<name>=<value>
helm install myopenfoamjob examples/openfoam-job-yunikorn --set acrName=${acr_name}

```
You can watch the job output by using the kubectl logs command after you got the first pod's name that starts with myopenfoamjob-0.  Get the pods with `kubectl get pods`:

```
NAME                       READY   STATUS    RESTARTS   AGE
install-mlx-driver-c8wz4   1/1     Running   0          4h45m
install-mlx-driver-zkxpd   1/1     Running   0          4h45m
myopenfoamjob-0-rqznw       1/1     Running   0          5m17s
myopenfoamjob-1-qlblr       1/1     Running   0          5m17s
```

And, view the logs with `kubectl logs myopenfoamjob-0-rqznw`:

```
streamlines streamlines write:
    Seeded 20 particles
    Sampled 32580 locations
forceCoeffs forceCoeffs1 write:
    Cm    = 0.156646
    Cd    = 0.406473
    Cl    = 0.071285
    Cl(f) = 0.192289
    Cl(r) = -0.121004

End

Finalising parallel run
Running reconstructParMesh on /home/hpcuser/motorbike_scaled
```

To cleanup the job, just run the helm unistall command:
```
helm uninstall myopenfoamjob
```

## Using local NVME as scratch

### Installation

This implementation is based on the aks-nvme-ssd-provisioner from Alessando Vozza (https://github.com/ams0/aks-nvme-ssd-provisioner).

We modify the manifests to create a persistent volume claim for each compute node and to mount the disk or raidset under `/pv-disks/scratch` on the host.  This provides a consistent place to add for the kubernetes indexed jobs. 

First we clone the repository and enter the directory:
```
git clone https://github.com/ams0/aks-nvme-ssd-provisioner
cd aks-nvme-ssd-provisioner
```
Then we change the mountpoint and create the docker container and upload it into our container registry:
```
sed -i "s/\/pv-disks\/\$UUID/\/pv-disks\/scratch/g" aks-nvme-ssd-provisioner.sh
sed -i "/^COPY .*$/a RUN chmod +x \/usr\/local\/bin\/aks-nvme-ssd-provisioner.sh" Dockerfile
docker build -t ${acr_name}.azurecr.io/aks-nvme-ssd-provisioner:v1.0.2 .
docker push ${acr_name}.azurecr.io/aks-nvme-ssd-provisioner:v1.0.2
```
The next step conisists in modifying container registry in the manifest and change the name of the label:
```
sed -i "s/ams0/${acr_name}.azurecr.io/g" ./manifests/storage-local-static-provisioner.yaml
sed -i "s/kubernetes.azure.com\/aks-local-ssd/aks-local-ssd/g" ./manifests/storage-local-static-provisioner.yaml
```
Now we are ready to deploy the manifest and leave the directory:
```
kubectl apply -f manifests/storage-local-static-provisioner.yaml
```
The manifest creates the following kubernetes resources:

*	clusterrolebinding.rbac.authorization.k8s.io/local-storage-provisioner-pv-binding
*	clusterrole.rbac.authorization.k8s.io/local-storage-provisioner-node-clusterrole
*	clusterrolebinding.rbac.authorization.k8s.io/local-storage-provisioner-node-binding
*	serviceaccount/local-storage-admin
*	configmap/local-provisioner-config
*	daemonset.apps/local-volume-provisioner
*	storageclass.storage.k8s.io/local-storage

To apply the changes to the nodepool hb120v2, we need to run the following command to add the label aks-local-ssd:
```
az aks nodepool update -g ${resource_group} --cluster-name ${aks_cluster_name} -n hb120v2 --labels aks-local-ssd=true
```

### Testing with FIO

The example, `examples/fio-nvme-job.yaml`, runs a simple benchmark to test the performance of the local NVME.  This is based on the Ubuntu 20.04 base container, installs fio and runs a test.  Run as follows:

```
kubectl apply -f examples/fio-nvme-job.yaml
```

Here is example output:

```
write_16G: (g=0): rw=write, bs=(R) 4096KiB-4096KiB, (W) 4096KiB-4096KiB, (T) 4096KiB-4096KiB, ioengine=psync, iodepth=1
fio-3.16
Starting 1 process

write_16G: (groupid=0, jobs=1): err= 0: pid=787: Wed Nov  2 12:21:49 2022
  write: IOPS=259, BW=1038MiB/s (1089MB/s)(16.0GiB/15780msec); 0 zone resets
    clat (usec): min=3184, max=52027, avg=3822.21, stdev=1200.04
     lat (usec): min=3202, max=52056, avg=3851.71, stdev=1200.11
    clat percentiles (usec):
     |  1.00th=[ 3425],  5.00th=[ 3425], 10.00th=[ 3458], 20.00th=[ 3458],
     | 30.00th=[ 3458], 40.00th=[ 3458], 50.00th=[ 3490], 60.00th=[ 3589],
     | 70.00th=[ 3785], 80.00th=[ 4293], 90.00th=[ 4621], 95.00th=[ 4817],
     | 99.00th=[ 5669], 99.50th=[ 6456], 99.90th=[ 8225], 99.95th=[ 8455],
     | 99.99th=[52167]
   bw (  MiB/s): min=  952, max= 1064, per=99.97%, avg=1037.94, stdev=26.13, samples=31
   iops        : min=  238, max=  266, avg=259.48, stdev= 6.53, samples=31
  lat (msec)   : 4=75.10%, 10=24.85%, 100=0.05%
  cpu          : usr=0.85%, sys=2.71%, ctx=4101, majf=0, minf=10
  IO depths    : 1=100.0%, 2=0.0%, 4=0.0%, 8=0.0%, 16=0.0%, 32=0.0%, >=64=0.0%
     submit    : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     complete  : 0=0.0%, 4=100.0%, 8=0.0%, 16=0.0%, 32=0.0%, 64=0.0%, >=64=0.0%
     issued rwts: total=0,4096,0,0 short=0,0,0,0 dropped=0,0,0,0
     latency   : target=0, window=0, percentile=100.00%, depth=1

Run status group 0 (all jobs):
  WRITE: bw=1038MiB/s (1089MB/s), 1038MiB/s-1038MiB/s (1089MB/s-1089MB/s), io=16.0GiB (17.2GB), run=15780-15780msec

Disk stats (read/write):
  nvme0n1: ios=0/133975, merge=0/0, ticks=0/251799, in_queue=18980, util=99.45%
```
## Run the Devito using Helm and YuniKorn

The file `examples/dvito-job-yunikorn/values.yaml` containes the job parameters which can be adjusted or overridden:

```
# Devito Job parameters
userName: hpcuser
userId: 10000
groupName: hpcuser
groupId: 10000
procsPerNode: 120
numberOfNodes: 2
acrName: 
blobStorageAccountName:
sasToken:
```
Create a output storage account: 
```
az login
# TODO: set the account name and container name below
account_name=

az storage account create \
  --name ${account_name} \
  --resource-group ${resource_group} \
  --location westeurope \
  --sku Standard_LRS \
  --kind StorageV2

start_date=$(date +"%Y-%m-%dT%H:%M:%SZ")
expiry_date=$(date +"%Y-%m-%dT%H:%M:%SZ" --date "next month")
```
Create a SAS token:
```
sas_token=$(az storage account generate-sas \
   --account-name ${account_name} \
   --permissions acdlruwap \
   --service b \ 
   --resource-types co \
   --permissions rwld \
   --start $start_date \
   --expiry $expiry_date \
   -o tsv)
```
The sas_token shpuld start with a "s". I case you create a toke through the Azure portal, please remove the "&" at the beginning. 

The job will create a blob container with the name of the helm chart to store the results.

To run the Devito job
```
# helm install <release-name> <chart> --set <name>=<value>,<name>=<value>
helm install mydevitojob examples/devito-job-yunikorn \
  --set acrName=${acr_name} \ 
  --set blobStorageAccountName=${account_name} \
  --set sasToken=${sas_token}
```
You can watch the job output by using the kubectl logs command after you got the first pod's name that starts with myopenfoamjob-0.  Get the pods with `kubectl get pods`:
```
NAME                                                  READY   STATUS          RESTARTS      AGE
install-mlx-driver-j962m                              1/1     QuotaApproved   5 (42m ago)   44m
install-mlx-driver-rdn9k                              1/1     QuotaApproved   0             44m
mydevitojob-0-ns58r                                   1/1     QuotaApproved   0             114s
mydevitojob-1-rxsgh                                   1/1     QuotaApproved   0             114s
```
And, view the logs with `kubectl logs mydevitojob-0-ns58r`:
```
[      0 ] Starting SSH daemon
 * Starting OpenBSD Secure Shell server sshd
   ...done.
[      0 ] Creating IP file (/home/jobs/mydevitojob/hosts/10.244.8.7)
[      1 ] Adding user with homedir (hpcuser)
Adding group `hpcuser' (GID 10000) ...
Done.
Adding user `hpcuser' ...
Adding new user `hpcuser' (10000) with group `hpcuser' ...
Creating home directory `/home/hpcuser' ...
Copying files from `/etc/skel' ...
[      1 ] User added ()
[      1 ] Creating ssh key
[      1 ] Waiting for hosts
[      1 ] Creating hostfile
[      1 ] Hostfile contents:
10.244.8.7
10.244.9.7
[      1 ] Launching MPI
Loading mpi/hpcx
  Loading requirement:
    /opt/hpcx-v2.11-gcc-MLNX_OFED_LINUX-5-ubuntu20.04-cuda11-gdrcopy2-nccl2.11-x86_64/modulefiles/hpcx

Successfully created the resource.
Warning: Permanently added '10.244.9.7' (ECDSA) to the list of known hosts.
Starting the job ...
Starting the job ...
Starting the job ...
Starting the job ...
Starting the job ...
Starting the job ...
Starting the job ...
Starting the job ...
Starting the job ...
Starting the job ...
Starting the job ...
...
...
...
Elapsed time is 201.81673884391785 s
ended simulation
wavefield size  (2, 56, 32, 64)
model size  (56, 32, 64)
wavefield size  (2, 56, 32, 64)
model size  (56, 32, 64)
model size  (56, 32, 64)
model size  (56, 32, 64)
INFO: Scanning...
INFO: Any empty folders will not be processed, because source and/or destination doesn't have full folder support

Job 18e2c32c-599d-7f47-4fa3-677be52667a3 has started
Log file is located at: /home/hpcuser/.azcopy/18e2c32c-599d-7f47-4fa3-677be52667a3.log


100.0 %, 5 Done, 0 Failed, 0 Pending, 0 Skipped, 5 Total, 2-sec Throughput (Mb/s): 0.7774


Job 18e2c32c-599d-7f47-4fa3-677be52667a3 summary
Elapsed Time (Minutes): 0.0334
Number of File Transfers: 5
Number of Folder Property Transfers: 0
Total Number of Transfers: 5
Number of Transfers Completed: 5
Number of Transfers Failed: 0
Number of Transfers Skipped: 0
TotalBytesTransferred: 194611
Final Job Status: Completed

[    305 ] Writing completion file (/home/jobs/mydevitojob/complete)
[    305 ] Exiting, status: success)
```
To cleanup the job, just run the helm unistall command:
```
helm uninstall mydevitojob
```
