#!/bin/bash

echo "Running an OpenFoam job"

source /etc/profile
module load mpi/hpcx
source /opt/openfoam10/etc/bashrc

CASE_NAME=motorbike_scaled
CORES=240
PPN=120

cp -r $WM_PROJECT_DIR/tutorials/incompressible/simpleFoam/motorBike $CASE_NAME
cd $CASE_NAME

# increase blockmesh size
sed -i 's/(20 8 8)/(40 16 16)/g' system/blockMeshDict

# Determine X,Y,Z based on total cores
if [ "$(($PPN % 4))" == "0" ]; then
    X=$(($CORES / 4))
    Y=2
    Z=2
elif [ "$(($PPN % 6))" == "0" ]; then
    X=$(($CORES / 6))
    Y=3
    Z=2
else
    echo "Incompataible value of PPN: $PPN. Try something that is divisable by 4,6, or 9"
    exit -1
fi
echo "X: $X, Y: $Y, Z: $Z"

# set up decomposition
sed -i "s/numberOfSubdomains  6;/numberOfSubdomains $CORES;/g" system/decomposeParDict
sed -i "s/(3 2 1);/(${X} ${Y} ${Z});/g" system/decomposeParDict

# update runParallel to add MPI flags
sed -i "s/runParallel\( *\([^ ]*\).*\)$/mpirun -np $CORES --map-by ppr:${PPN}:node -hostfile ~\/hostfile -x LD_LIBRARY_PATH -x UCX_TLS=rc -x PATH $(env |grep FOAM | cut -d'=' -f1 | sed 's/^/-x /g' | tr '\n' ' ') $(env |grep WM | cut -d'=' -f1 | sed 's/^/-x /g' | tr '\n' ' ') -x MPI_BUFFER_SIZE \1 -parallel 2\>\&1 |tee log\.\2/g" Allrun

./Allrun