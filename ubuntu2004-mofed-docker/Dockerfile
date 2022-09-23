FROM ubuntu:20.04

RUN apt-get update && DEBIAN_FRONTEND="noninteractive" TZ="Europe/London" \
        apt-get -o apt::install-recommends=false install -y tzdata curl git gnupg2 wget pciutils net-tools iproute2 libnl-3-dev libnl-route-3-dev udev openssh-server openssh-client perl sudo ca-certificates 

WORKDIR /tmp/

ENV MOFED_VER 5.6-2.0.9.0
ENV OS_VER ubuntu20.04
ENV PLATFORM x86_64

RUN curl -L https://content.mellanox.com/ofed/MLNX_OFED-${MOFED_VER}/MLNX_OFED_LINUX-${MOFED_VER}-${OS_VER}-${PLATFORM}.tgz -o MLNX_OFED.tgz && \
        tar -xzvf MLNX_OFED.tgz && \
        MLNX_OFED_LINUX-${MOFED_VER}-${OS_VER}-${PLATFORM}/mlnxofedinstall --user-space-only --without-fw-update --all --force
RUN rm MLNX_OFED.tgz
RUN rm -rf /tmp/MLNX_OFED_LINUX-${MOFED_VER}-${OS_VER}-${PLATFORM}

## HPC tuning
RUN echo '\
*               hard    memlock         unlimited\n\
*               soft    memlock         unlimited\n\
*               hard    nofile          65535\n\
*               soft    nofile          65535\n\
*               hard    stack           unlimited\n\
*               soft    stack           unlimited' >> /etc/security/limits.conf

## install azcopy
RUN cd /usr/bin && \
        wget -q https://aka.ms/downloadazcopy-v10-linux -O - | tar zxf - --strip-components 1 --wildcards '*/azcopy' && \
        chmod 755 /usr/bin/azcopy
