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
acr_name=$(jq -r .properties.outputs.acrName.value deploy-output.json)
```

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

Create hierarchy:

* OS Version with Mellanox driver
    * MPI Distribution
        * Application
    

* Ubuntu 20.04 + Mellanox
    * hpcx
        * OpenFOAM
        
### Ubuntu 20.04 conatiner with Mellanox OFED - ubuntu2004-mofed
```
pushd ubuntu2004-mofed-docker
docker build -t ${acr_name}.azurecr.io/ubuntu2004-mofed .
docker push ${acr_name}.azurecr.io/ubuntu2004-mofed
popd
```

### HPCX MPI layer on top of the previous container image. - ubuntu2004-mofed-hpcx
```
pushd ubuntu2004-mofed-hpcx-docker
sed "s/__ACRNAME__/${acr_name}/g" Dockerfile.template > Dockerfile
docker build -t ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx .
docker push ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx
popd

```



## Launching

* Multiple pods
    * 1 per host
* TODO: Get IP addresses for hostfile
* Launch mpirun on one pod

```
kubectl apply -f testmpi.yaml
kubectl exec -it mpi-pod1 -- bash

sudo su - hpcuser
mkdir /home/hpcuser
cd /home/hpcuser
ssh-keygen

cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys
sudo service ssh start


```

hpcx env (should use modules here)
```
. /opt/hpcx-v2.11-gcc-MLNX_OFED_LINUX-5-ubuntu20.04-cuda11-gdrcopy2-nccl2.11-x86_64/hpcx-init-ompi.sh
hpcx_load
```

look it works :-)
```
hpcuser@mpi-pod1:~$ mpirun -np 2 -host 10.244.3.7:1,10.244.4.7:1 -x LD_LIBRARY_PATH -x UCX_TLS=rc -report-bindings /opt/hpcx-v2.11-gcc-MLNX_OFED_LINUX-5-ubuntu20.04-cuda11-gdrcopy2-nccl2.11-x86_64/ompi/tests/imb/IMB-MPI1 PingPong
[mpi-pod1:00232] MCW rank 0 bound to socket 0[core 0[hwt 0]]: [B/././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
[mpi-pod2:00170] MCW rank 1 bound to socket 0[core 0[hwt 0]]: [B/././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.][./././././././././././././././././././././././././././././././././././././././././././././././././././././././././././.]
#------------------------------------------------------------
#    Intel (R) MPI Benchmarks 2018, MPI-1 part
#------------------------------------------------------------
# Date                  : Fri Sep  9 16:54:32 2022
# Machine               : x86_64
# System                : Linux
# Release               : 5.4.0-1089-azure
# Version               : #94~18.04.1-Ubuntu SMP Fri Aug 5 12:34:50 UTC 2022
# MPI Version           : 3.1
# MPI Thread Environment:


# Calling sequence was:

# /opt/hpcx-v2.11-gcc-MLNX_OFED_LINUX-5-ubuntu20.04-cuda11-gdrcopy2-nccl2.11-x86_64/ompi/tests/imb/IMB-MPI1 PingPong

# Minimum message length in bytes:   0
# Maximum message length in bytes:   4194304
#
# MPI_Datatype                   :   MPI_BYTE
# MPI_Datatype for reductions    :   MPI_FLOAT
# MPI_Op                         :   MPI_SUM
#
#

# List of Benchmarks to run:

# PingPong

#---------------------------------------------------
# Benchmarking PingPong
# #processes = 2
#---------------------------------------------------
       #bytes #repetitions      t[usec]   Mbytes/sec
            0         1000         1.69         0.00
            1         1000         1.69         0.59
            2         1000         1.68         1.19
            4         1000         1.74         2.30
            8         1000         1.69         4.73
           16         1000         1.70         9.43
           32         1000         1.89        16.94
           64         1000         1.97        32.49
          128         1000         2.02        63.29
          256         1000         2.61        97.97
          512         1000         2.75       185.89
         1024         1000         2.78       368.82
         2048         1000         3.06       670.01
         4096         1000         3.74      1095.95
         8192         1000         4.25      1926.70
        16384         1000         5.53      2962.20
        32768         1000         7.56      4334.91
        65536          640        10.82      6057.67
       131072          320        16.79      7805.51
       262144          160        19.38     13529.41
       524288           80        30.17     17375.04
      1048576           40        52.75     19878.20
      2097152           20        97.51     21506.12
      4194304           10       183.81     22818.79


# All processes entering MPI_Finalize

hpcuser@mpi-pod1:~$
```


### OpenFoam v10 container. - ubuntu2004-mofed-hpcx-openfoam

```
pushd ubuntu2004-mofed-hpcx-openfoam-docker
sed "s/__ACRNAME__/${acr_name}/g" Dockerfile.template > Dockerfile
docker build -t ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx-openfoam .
docker push ${acr_name}.azurecr.io/ubuntu2004-mofed-hpcx-openfoam
popd

```
