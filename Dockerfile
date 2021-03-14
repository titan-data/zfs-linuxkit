ARG ZFS_VERSION=0.8.2
ARG KERNEL_IMAGE=linuxkit/kernel:5.4.39
ARG ALPINE_VERSION=e2391e0b164c57db9f6c4ae110ee84f766edc430

FROM ${KERNEL_IMAGE} AS ksrc
FROM linuxkit/alpine:${ALPINE_VERSION} AS build
ARG ZFS_VERSION
ARG KERNEL_IMAGE

RUN apk update
RUN apk add bash \
    attr-dev \
    autoconf \
    automake \
    build-base \
    curl \
    elfutils-dev \
    gettext-dev \
    git \
    gettext-dev \
    kmod \
    linux-headers \
    libtirpc-dev \
    libintl \
    libressl-dev \
    libtool \
    musl-utils \
    util-linux-dev \
    zlib-dev \
    zfs-libs

COPY --from=ksrc /kernel-dev.tar /
RUN tar xf kernel-dev.tar
RUN ls -1d /usr/src/linux-headers-*-linuxkit | sed 's#/usr/src/linux-headers-##g' > /etc/kernel-version

# now download and build openzfs
RUN git clone https://github.com/zfsonlinux/zfs /src/zfs
WORKDIR /src/zfs
RUN git checkout zfs-${ZFS_VERSION}
RUN sh ./autogen.sh
RUN ./configure \
  --prefix=/ \
  --libdir=/lib \
  --includedir=/usr/include \
  --datarootdir=/usr/share \
  --with-linux=/usr/src/linux-headers-$(cat /etc/kernel-version) \
  --with-linux-obj=/usr/src/linux-headers-$(cat /etc/kernel-version) \
  --with-config=all

RUN make -s -j$(nproc)
RUN make install
RUN depmod $(cat /etc/kernel-version)

# we will need this link
RUN ln -s /lib/modules/$(cat /etc/kernel-version)/modules.builtin /lib/modules/$(cat /etc/kernel-version)/modules.builtin 

FROM alpine:3.13
COPY --from=build /etc/kernel-version /etc/kernel-version
# install it to a separate dedicated directory, because we don't want to mess up the main one
# also, the main one is loaded read-only
# we do this in 2 steps, because we need to derive the kernel version by reading it from /etc/kernel-version
# we cannot use the output of that in the COPY step
COPY --from=build /lib/modules /lib/modules
RUN mv /lib/modules/$(cat /etc/kernel-version) /lib/modules/$(cat /etc/kernel-version)-zfs

RUN apk add kmod

# this way the container just loads the module when run
CMD modprobe -S $(uname -r)-zfs zfs 
