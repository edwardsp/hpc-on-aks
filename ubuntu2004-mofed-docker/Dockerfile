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
