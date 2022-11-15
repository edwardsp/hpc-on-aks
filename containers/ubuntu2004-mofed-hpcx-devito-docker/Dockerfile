# Devito dockerfile
ARG ACR_NAME
FROM $ACR_NAME.azurecr.io/ubuntu2004-mofed-hpcx:latest

ENV DEVITO_VER 4.7.1

LABEL org.opencontainers.image.source="https://github.com/edwardsp/hpc-on-aks"
LABEL org.opencontainers.image.url="https://github.com/edwardsp/hpc-on-aks"
LABEL org.opencontainers.image.title="${OS_NAME} ${OS_VER} with Devito ${DEVITO_VER}"
LABEL org.opencontainers.image.description="${OS_NAME} ${OS_VER} with Devito ${DEVITO_VER}, Mellanox drivers v${MOFED_VER}, HPCX v${HPCX_VER}"
LABEL org.opencontainers.image.base.name="${OS_NAME}${OS_VER}-mofed-hpcx:latest"

##################  Install devito ############################################
# Set OpenMPI path

RUN apt-get update \
    && DEBIAN_FRONTEND="noninteractive" TZ="Europe/London" apt-get -o apt::install-recommends=false install -y pkg-config python3-dev htop \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Devito env
ENV DEVITO_ARCH="gcc-9"
ENV DEVITO_PLATFORM="cpu64"
ENV DEVITO_LANGUAGE="openmp"

# Install pip dependencies and devito as a pip package
RUN . /etc/profile.d/modules.sh && \
    module load mpi/hpcx && \
    export MPICC=$(which mpicc) && \
    python3 -m pip install matplotlib mpi4py ipyparallel segyio git+https://github.com/devitocodes/devito.git@v${DEVITO_VER}