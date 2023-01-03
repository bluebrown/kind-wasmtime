# Kind Wasmtime

Create a kind cluster with support for wasm workloads using wasmtime through
crun.

## Synopsis

The Makefile contains instructions to build the custom kind node and create the
cluster as well as running a test workload.

```console
Usage:
  make [ COMMAND ] [ OPTION=VALUE ]...

Options:
  KUBE_VERSION      (default: 1.24.6)
  WASMTIME_VERSION  (default: 4.0.0)
  CRUN_VERSION      (default: 1.7.2)
  SHIMS_VERSION     (default: 0.3.3)

Commands:
  help              Display this help text
  clean             Delete the kind cluster
  all               Build cluster and run the example workloads
  cluster           Create the cluster
  node-image        Build the custom kind node image
  crun-workload     Build a wasm workload image and load it into kind
  crun-test         Deploy a test job with mixed workloads and print their logs
  spin-workload     Build a wasm app with spin and load it into kind
  spin-test         Deploy the spin app and curl its output
```

## How it works

crun is build from source with wasmtime supported enabled. The crun build is
added to a kind node image image and added to its containerd config file as
additional runtime. That way, container d will still use the default runc as
container runtime unless the crun-wasmtime runtime is explcitily selected via
kubernetes runtime class.

Review the [Dockerfile](./kind-wasmtime/node-image/Dockerfile) for details.

### Building crun

The important part is to tell [crun](https://github.com/containers/crun) to
enable wasmtime support.

```bash
./configure --with-wasmtime
```

It requires the wasmtime c libraries to be availble in the system. The c api can
be fetched from the [release
page](https://github.com/bytecodealliance/wasmtime/releases).

See also:

- <https://github.com/containers/crun/blob/main/docs/wasm-wasi-example.md>

### Configuring containerd

In the kind node image is already a containerd config.toml. So we only need to
add the crun-wasmtime runtime configuration to it. This will make the runtime
available but not use it as default, as runc is the configured default.

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.crun-wasmtime]
runtime_type = "io.containerd.runc.v2"
base_runtime_spec = "/etc/containerd/cri-wasm.json"
pod_annotations = ["module.wasm.image/*"]

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.crun-wasmtime.options]
BinaryName = "/usr/local/bin/crun"
SystemdCgroup = true
```

It is important that we allow the wasm related pod annotations to propagate down
to the oci spec. These annotations can tell crun how to behave. For example by
using `module.wasm.image/variant: compat-smart`, we can tell crun that we want
to use wasmtime to run workloads but only where applicable. So crun tries to me
*smart* and figure out when to actually use wasmtime. This allows to run pods
with mixed workloads as seen in the [example job](./example.yaml).

See also:

- <https://github.com/containerd/containerd/blob/main/docs/man/containerd-config.toml.5.md>
- <https://github.com/containerd/containerd/blob/main/docs/cri/config.md#full-configuration>

### OCI Annotations

As metioned in the previous section, oci wasm annotation can be used to control
the behvior of the runtime. It is possible to use the cri config json file, to
set these annotations automatically for each workload that is using the runtime.
For this we want to add the annotations property to the cri-base.json

```json
"annotations": {
  "module.wasm.image/variant": "compat-smart"
}
```

We can do this by merging the default config from the image. If you look at the
containerd runtime config in the previous section, you see that it is using the
*cri-wasm.json* as `base_runtime_spec`.

```bash
jq -s '.[0] * .[1]' cri-base.json annotations.json > cri-wasm.json
```

This way, we only need to specify the runtime class in our pod.

See also:

- <https://github.com/opencontainers/runtime-spec/blob/main/config.md>

### Kubernetes runtime class

A [runtime class](./kind-wasmtime/runtime-class.yaml) is applied to the cluster.

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: crun-wasmtime
handler: crun-wasmtime
scheduling:
  nodeSelector:
    runtime/wasmtime: "true"
```

The handler corresponds to the name in the containerd config.toml
`plugins."io.containerd.grpc.v1.cri".containerd.runtimes.crun-wasmtime`.

Pods can be configured to use this runtime class in order to use crun as engine
by referncing its name in `.spec.runtimeClassName`.

See also:

- <https://kubernetes.io/docs/concepts/containers/runtime-class/>

### Example

As mentioned earlier, by using `compat-smart` in conjuction with the
`crun-wasmtime` runtime class, we can run pods with mixed workload types.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  runtimeClassName: crun-wasmtime
  containers:
    - name: wasm
      image: wasm-workload
    - name: oci
      image: oci-workload
```

## deislabs wasm shims

Since wasm/wasi is stil in its early stages, many things that would just work in
a regular container dont work out of the box when using wasm. For example, many
application expose an http interface.

There are some frameworks such as spin and slight to ease the implementation of
such services. You can use 2 [custom
shims](https://github.com/deislabs/containerd-wasm-shims) wrapping contained's
runwasi, created by deislabs in collaboration with microsoft, as they are using
them for their AKS wasm preview.

These shims do not support mixed workloads. Use one of the runtime classes
`wasmtime-spin-v1` or  `wasmtime-slight-v1` to run one of these workloads.

For example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wasm-slight
spec:
  selector:
    matchLabels:
      app: wasm-slight
  template:
    metadata:
      labels:
        app: wasm-slight
    spec:
      runtimeClassName: wasmtime-slight-v1
      containers:
        - name: testwasm
          image: ghcr.io/deislabs/containerd-wasm-shims/examples/slight-rust-hello:latest
          command: ["/"]
```
