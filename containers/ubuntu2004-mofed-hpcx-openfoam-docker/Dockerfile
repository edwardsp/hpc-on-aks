# Application image
ARG ACR_NAME
FROM $ACR_NAME.azurecr.io/ubuntu2004-mofed-hpcx:latest

ENV OPENFOAM_VER 10

LABEL org.opencountainers.image.source="https://github.com/edwardsp/hpc-on-aks"
LABEL org.opencountainers.image.url="https://github.com/edwardsp/hpc-on-aks"
LABEL org.opencountainers.image.title="${OS_NAME} ${OS_VER} with OpenFOAM ${OPENFOAM_VER}"
LABEL org.opencountainers.image.description="${OS_NAME} ${OS_VER} with OpenFOAM ${OPENFOAM_VER}, Mellanox drivers v${MOFED_VER}, HPCX v${HPCX_VER}"
LABEL org.opencountainers.image.base.name="${OS_NAME}${OS_VER}-mofed-hpcx:latest"

WORKDIR /root

# Install OpenFoam dependencies
RUN apt-get update \
    && DEBIAN_FRONTEND="noninteractive" TZ="Europe/London" apt-get -o apt::install-recommends=false install -y \
	  gnome-panel \
	  gnome-flashback \ 
	  gnome-session-flashback \ 
	  indicator-applet-appmenu \
	  software-properties-common \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install OpenFoam v10
RUN sh -c "wget -O - https://dl.openfoam.org/gpg.key > /etc/apt/trusted.gpg.d/openfoam.asc"
RUN add-apt-repository http://dl.openfoam.org/ubuntu
RUN apt-get update \
    && DEBIAN_FRONTEND="noninteractive" TZ="Europe/London" apt-get install -y \
    openfoam${OPENFOAM_VER} \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

