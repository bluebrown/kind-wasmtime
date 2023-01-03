ARG kubernetes_version=1.24.6

FROM ubuntu AS crun-builder

WORKDIR /ws
RUN apt-get update -y

# install base libs
RUN apt install -y \
  curl make git gcc build-essential pkgconf libtool libsystemd-dev libprotobuf-c-dev libcap-dev \
  libseccomp-dev libyajl-dev go-md2man libtool autoconf python3 automake

# get the wasmtime c api
ARG wasmtime_version=4.0.0
RUN curl -fsSL "https://github.com/bytecodealliance/wasmtime/releases/download/v${wasmtime_version}/wasmtime-v${wasmtime_version}-x86_64-linux-c-api.tar.xz" \
  | tar -C /usr/local --strip-components 1 --exclude LICENSE --exclude README.md -J -xf -

# compile crun with wasmtime support
ARG crun_version=1.7.2
RUN git clone --single-branch --branch "${crun_version}" https://github.com/containers/crun
WORKDIR /ws/crun
RUN ./autogen.sh
RUN ./configure --with-wasmtime --enable-embedded-yajl
RUN make

FROM "kindest/node:v${kubernetes_version}" as kind

# if cgroups are enabled on crun, dbus is required?!
# disabling cgroups is probably not good in case of mixed-workloads
RUN apt-get -y update
RUN apt-get -y install dbus

# get the wasm shims used by azure
# this allows to run spin and slight wasm apps
ARG shims_version=0.3.3
RUN curl -fsSL "https://github.com/deislabs/containerd-wasm-shims/releases/download/v${shims_version}/containerd-wasm-shims-v1-linux-x86_64.tar.gz" \
  | tar -C /usr/local/bin -xzf -

# get and link crun
COPY --from=crun-builder --chmod=755 /ws/crun/crun /usr/local/bin/crun
COPY --from=crun-builder /usr/local/lib/libwasmtime.so /usr/local/lib/libwasmtime.so
RUN ldconfig

# add the crun runtime handler to the containerd config
COPY containerd/* /tmp/
RUN cat /tmp/crun-wasmtime.toml >> /etc/containerd/config.toml

# add the shims to the containerd config
RUN cat /tmp/wasm-shims.toml >> /etc/containerd/config.toml

# create a cri config with default compat-smart annotation
RUN jq -s '.[0] * .[1]' /etc/containerd/cri-base.json /tmp/annotations.json > /etc/containerd/cri-wasm.json

