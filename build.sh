#!/bin/sh
set -e

# which images do we want to build?
target_image="$1"

[ -z "$target_image" ] && target_image=all

mkdir -p cache

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
  VERSION_TAG=$(echo $KERNEL_IMAGE | tr '/' '-' | tr ':' '-')
  echo "Building openzfs $ZFS_VERSION for $KERNEL_IMAGE with alpine $ALPINE_VERSION"
  docker build --build-arg ZFS_VERSION=$ZFS_VERSION --build-arg KERNEL_IMAGE=$KERNEL_IMAGE --build-arg ALPINE_VERSION=$ALPINE_VERSION  -t openzfs:install-${VERSION_TAG} .
  docker save openzfs:install-${VERSION_TAG} > cache/zfs-${VERSION_TAG}.tar
  echo "Creating linuxkit images for $KERNEL_IMAGE"
  for i in linuxkit-*.tmpl.yml; do
    outfile=$(echo $i | sed 's/.tmpl\.yml//g')
    outfile=cache/${outfile}-${VERSION_TAG}.yml
    cat $i | sed "s#KERNEL_IMAGE#${KERNEL_IMAGE}#g" | sed "s/VERSION_TAG/${VERSION_TAG}/g" > ${outfile}
    linuxkit build -dir cache --docker ${outfile}
    runfile=${outfile%%.yml}
    echo "${KERNEL_IMAGE} ready for test, run:"
    echo "  linuxkit run qemu -mem 2048 ${runfile}"
    echo " or"
    echo "  linuxkit run hyperkit -mem 2048 ${runfile}"
    echo
  done
done < versions


