# Application image
ARG ACR_NAME
FROM $ACR_NAME.azurecr.io/ubuntu2004-mofed:latest

ENV HPCX_VER "2.11"
ENV CUDA_VER "11"

LABEL org.opencountainers.image.source="https://github.com/edwardsp/hpc-on-aks"
LABEL org.opencountainers.image.url="https://github.com/edwardsp/hpc-on-aks"
LABEL org.opencountainers.image.title="${OS_NAME} ${OS_VER} with HPCX ${HPCX_VER}"
LABEL org.opencountainers.image.description="${OS_NAME} ${OS_VER} with Mellanox drivers v${MOFED_VER} and HPCX v${HPCX_VER}"
LABEL org.opencountainers.image.base.name="${OS_NAME}${OS_VER}-mofed:latest"


WORKDIR /root

# Download the repository configuration package

RUN curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list > /etc/apt/sources.list.d/microsoft-prod.list
RUN curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.gpg 

RUN apt-get update \
    && DEBIAN_FRONTEND="noninteractive" TZ="Europe/London" apt-get -o apt::install-recommends=false install -y \
                   numactl \
                   wget \
		   rpm \
                   libnuma-dev \
                   libmpc-dev \
                   libmpfr-dev \
                   libxml2-dev \
                   m4 \
                   byacc \
                   python-dev \
                   python-setuptools \
                   tcl \
                   environment-modules \
                   tk \
                   texinfo \
                   libudev-dev \
                   binutils \
                   binutils-dev \
                   selinux-policy-dev \
                   flex \
                   libnl-3-dev \
                   libnl-route-3-dev \
                   libnl-3-200 \
                   bison \
                   libnl-route-3-200 \
                   gfortran \
                   cmake \
                   libnl-3-dev \
                   libnl-route-3-dev \
                   net-tools \
                   libsecret-1-0 \
		   ansible \
		   python3-pip \
                   dkms \
                   vim \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*
## Install HPC-X

# HPC-X v2.11
ENV INSTALL_PREFIX /opt
ENV HPCX_TARBALL hpcx-v${HPCX_VER}-gcc-MLNX_OFED_LINUX-5-${OS_NAME}${OS_VER}-cuda${CUDA_VER}-gdrcopy2-nccl2.11-x86_64.tbz
ENV HPCX_DOWNLOAD_URL https://azhpcstor.blob.core.windows.net/azhpc-images-store/${HPCX_TARBALL}
ENV HPCX_FOLDER hpcx-v${HPCX_VER}-gcc-MLNX_OFED_LINUX-5-${OS_NAME}${OS_VER}-cuda${CUDA_VER}-gdrcopy2-nccl2.11-x86_64 

RUN wget --retry-connrefused --tries=3 --waitretry=5 ${HPCX_DOWNLOAD_URL} && \
	tar -xvf ${HPCX_TARBALL} && \
	mv ${HPCX_FOLDER} ${INSTALL_PREFIX}

ENV HPCX_PATH ${INSTALL_PREFIX}/${HPCX_FOLDER}
ENV PATH=${HPCX_PATH}/ucx/bin:${HPCX_PATH}/ompi/bin;${HPCX_PATH}/hcoll/bin:${HPCX_PATH}/clusterkit/bin:${PATH}
ENV LD_LIBRARY_PATH=${HPCX_PATH}/ucx/lib/ucx:${HPCX_PATH}/ucx/lib:${HPCX_PATH}/ompi/lib;${HPCX_PATH}/hcoll/lib:${LD_LIBRARY_PATH}
ENV CPATH=${HPCX_PATH}/hcoll/include:${HPCX_PATH}/ucx/include:${HPCX_PATH}/ompi/include:${CPATH}
ENV MPICC=${HPCX_PATH}/ompi/bin/mpicc

# HPC-X module
# Module Files
ENV MODULE_FILES_DIRECTORY /usr/share/modules/modulefiles/mpi
RUN mkdir -p ${MODULE_FILES_DIRECTORY}

RUN echo "#%Module 1.0\n#\n#  HPCx v${HPCX_VER}\n#\n\
conflict   mpi\n\
module load ${HPCX_PATH}/modulefiles/hpcx" >> ${MODULE_FILES_DIRECTORY}/hpcx-v${HPCX_VER}


# Softlinks
RUN ln -s ${MODULE_FILES_DIRECTORY}/hpcx-v${HPCX_VER} ${MODULE_FILES_DIRECTORY}/hpcx
