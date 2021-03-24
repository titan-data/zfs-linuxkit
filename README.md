Instructions on how to build the kernel module, then run a VM which loads it, for testing purposes.

## Kernel Versions

It is important to note that there are two nearly identical versions of the kernel, with the same version numbers, which can
affect creating and loading your module. Specifically, Docker Desktop _bases_ its kernels on [linuxkit/kernel](https://github.com/linuxkit/linuxkit/tree/master/kernel)
but doesn't always use it directly. It sometimes creates a derivative kernel, whose source is not open, but whose
image and build are available [on Docker Hub](http://hub.docker.com/r/docker/for-desktop-kernel).

Unfortunately, docker/for-desktop-kernel uses the _identical_ version number as the upstream linuxkit one, whether or not it is changed. This makes knowing that
it is different difficult.

Fortunately, the only difference that matters, in terms of compiling new kernels, is the `RAND_STRUCT_SEED` in
`usr/src/linux-headers-4.19.121-linuxkit/include/generated/randomize_layout_hash.h`. 

This gives us two options:

* build using the upstream linuxkit kernel, but override just that file
* build using the docker/for-desktop-kernel

Either way, we will need the specific kernel image. Docker does not publish a mapping anywhere of Desktop version -> kernel version. The only way to get the right version is:

1. Launch docker desktop of the desired version
1. Run `docker run --rm -it --privileged --pid=host alpine:latest nsenter -t 1 -m -u -n -i awk '/image: docker\/for-desktop-kernel:/ {print $2}' /etc/linuxkit.yml`

There is no way to get the Docker Desktop version via the `docker` CLI, so you just have to know it.

NOTE: Docker is considering tagging the kernels with the desktop to make it east to reference, e.g. `docker/for-desktop-kernel:desktop-3.3.0.1`


## Docker image

The Dockerfile in this repository builds the openzfs kernel module, saves it in a simple image, and then can be run to load it.
Once you have the image ready, you need simply do:

```
docker run --rm --privileged <image>
```

and the kernel modules will be loaded.

### Building the Docker Image

Run:

```
./build.sh
```

This will build all known versions in the file [versions](./versions) and tag them with the appropriate kernel version, e.g. `openzfs:install-5.4.39`.

If you want to build a specific version:

```
./build.sh <version>
```

Of course, it has to be a version supported in the [versions](./versions) file.

The versions `all` is a way to indicate to build all known versions, which is the same as not providing a version.

The build script also creates the `cache/` directory and saves the image to `cache/zfs-<kernel_version>.tar`

If you want to build the image directly, you can. You must get the build args correct for it to work:

```
docker build -t openzfs:install-<version> --build-arg ZFS_VERSION=<zfs_version> --build-arg LKT_VERSION=<linuxkit_kernel_version> --build-arg ALPINE_VERSION=<appropriate_alpinne_version> .
```

Optionally, push the images you build to a registry.

## Testing the Docker Image

This repository also contains LinuxKit configuration file templates for building LinuxKit images, which are bootable as a VM and can load the zfs driver.

The linuxkit yml files included in this repository are templates. When you run `build.sh`, it also generates the correct linuxkit yml files in `cache/`,
as well as the LinuxKit VM images, which you can then run to test the docker images.

The generated images have several options for loading the modules in the VM:

* load on boot - the linuxkit file to run ends in `*boot.yml`
* boot, and the manually `docker run` - the linuxkit file to run ends in `*docker.yml`

Whichever path you choose, when the module is loaded, run `lsmod` to check for it.

The `*docker.yml` version preloads the saved image as a local tar file.

When `build.sh` is complete, it will tell you which command-line to run to launch the image. Specifically, it will be:

```
linuxkit run qemu -mem 2048 cache/<image>      # for Linux
# or
linuxkit run hyperkit -mem 2048 cache/<image>  # for macOS
```

The `<image>` above is the name of the image, which is derived from the bsae kernel docker image used. For example, if the base kernel
was `linuxkit/kernel:5.4.39`, then the linuxkit run command would be `linuxkit run -mem 2048 cache/linuxkit-boot-linuxkit-kernel-5.4.39` or
`linuxkit run -mem 2048 cache/linuxkit-docker-linuxkit-kernel-5.4.39`.

If you are using the `docker run` option, you need to get from the getty shell to a docker cli.
You can get to it via `ctr -n services.linuxkit t exec --tty --exec-id=999 docker sh`, which will give you a shell which has `docker` commands available

1. OPTIONAL: load the saved image: `docker load < /images/zfs.tar` - if you are pulling the image from a registry, ignore this step
1. run the loader image: `docker run --rm --privileged <image>`
1. check that you have the module installed: `lsmod`

## Loading into Docker Desktop

To load into an active running Docker Desktop, you just need to run the image. In all cases, ensure you run it with `docker run --privileged --rm <image>`.

### Local

To run it where you built it:

1. Determine the proper kernel image version and create an image for it; see above
1. To load it, run `docker run --privileged --rm <image>`, e.g. `docker run --privileged --rm openzfs:install-docker-for-desktop-kernel-4.19.121-77626c0840805a2fe3f986674e9e6c5356a33f0c`

### Remote

If you want to run it on a different Docker Desktop than the one on which you built it, you need to distribute it, either via registry or sideload.

#### Registry

1. Tag the image with the name to which you will push it to the registry, e.g. `docker tag openzfs:install-docker-for-desktop-kernel-4.19.121-77626c0840805a2fe3f986674e9e6c5356a33f0c myname/install-zfs:docker-desktop-3.2.2`
1. Push the image, e.g. `docker push myname/install-zfs:docker-desktop-3.2.2`
1. On the remote node, run the image, e.g. `docker run --privileged --rm myname/install-zfs:docker-desktop-3.2.2`

#### Sideload

The build process already saved the image to cache as a tar file.

1. Copy the tar file to the remote node, e.g via `scp`
1. Load the tar file, e.g. `docker load < imagefile.tar`
1. Run the image, e.g. `docker run --privileged --rm openzfs:install-docker-for-desktop-kernel-4.19.121-77626c0840805a2fe3f986674e9e6c5356a33f0c`

## useful

Reminder: if you need to enter the PID 1 namespace and working dir use: `nsenter -t 1 -m -u -n -i sh`

