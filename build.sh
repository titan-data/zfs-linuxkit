#!/bin/sh
set -e

# which images do we want to build?
target_image="$1"
ver_tag=$2

[ -z "$target_image" ] && target_image=all

mkdir -p cache

# determine our platform
platform=$(uname -s)
platform=$(echo ${platform} | tr '[:upper:]' '[:lower:]')
hypervisor=""
case ${platform} in
linux)
  hypervisor=qemu
  ;;
darwin)
  hypervisor=hyperkit
  ;;
*)
  echo "Unknown platform ${platform}"
  exit 1
esac

# determine our arch
arch=$(uname -m)
arch_tag=""
case ${arch} in
  x86_64) arch_tag="amd64" ;;
  arm64) arch_tag="arm64" ;;
esac

outlines=""

# read the versions file to see what we support
while read -r line; do
  # ignore lines that start with #
  case "$line" in
  \#*)
    continue
  esac
  # get the matched versions from the line
  KERNEL_IMAGE="${line%% *}"
  ZFS_VERSION="${line##* }"
  ALPINE_VERSION="${line% *}"
  ALPINE_VERSION="${ALPINE_VERSION##* }"
  # we only process this line if it matches our version, or was all
  if [ "$target_image" != "$KERNEL_IMAGE" -a "$target_image" != "all" ]; then
    continue
  fi
  outlines="${outlines}\n${KERNEL_IMAGE} ready for test, run:"
  VERSION_TAG=$(echo $KERNEL_IMAGE | tr '/' '-' | tr ':' '-')
  echo "Building openzfs $ZFS_VERSION for $KERNEL_IMAGE with alpine $ALPINE_VERSION"
  docker buildx build --build-arg ZFS_VERSION=$ZFS_VERSION --build-arg KERNEL_IMAGE=$KERNEL_IMAGE --build-arg ALPINE_VERSION=$ALPINE_VERSION  -t openzfs:install-${VERSION_TAG} --load .
  echo "Built image, saving"
  docker save openzfs:install-${VERSION_TAG} > cache/zfs-${VERSION_TAG}.tar
  echo "Creating linuxkit images for $KERNEL_IMAGE"
  for i in linuxkit-*.tmpl.yml; do
    outfile=$(echo $i | sed 's/.tmpl\.yml//g')
    outfile=cache/${outfile}-${VERSION_TAG}
    outfilesize=${#outfile}
    if [ $outfilesize -gt 80 ]; then
      if echo "$outfile" | grep -E '([a-f0-9]){40}$'; then
        outfile=$(echo $outfile | sed 's/.\{33\}$//')
      else
         echo "outfile name would be ${outfile}, which is longer than the maximum 90 characters, cannot proceed"
         exit 1
      fi
    fi

    # check if the outfile is too long
    # the maximum allowed in a socket file is 108, see https://man7.org/linux/man-pages/man7/unix.7.html
    # and hyperkit adds another 18, so the max is 90. If it is longer than that, try to truncate a hash, if we can

    outfile=${outfile}.yml
    cat $i | sed "s#KERNEL_IMAGE#${KERNEL_IMAGE}#g" | sed "s/VERSION_TAG/${VERSION_TAG}/g" > ${outfile}
    linuxkit build -dir cache --docker ${outfile}
    runfile=${outfile%%.yml}
    outlines="${outlines}\n  linuxkit run ${hypervisor} -mem 2048 ${runfile}"

    #tag final image
    docker tag openzfs:install-${VERSION_TAG} titandata/docker-desktop-zfs-kernel:${ver_tag}-${arch_tag}
  done
done < versions

echo $outlines


