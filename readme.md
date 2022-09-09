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

## Launching

* Multiple pods
    * 1 per host
* TODO: Get IP addresses for hostfile
* Launch mpirun on one pod