FROM --platform=amd64 rust as build
WORKDIR /build
RUN rustup target add wasm32-wasi
COPY greet.rs .
RUN rustc greet.rs --target wasm32-wasi

FROM --platform=wasi/wasm32 scratch
COPY --from=build --chmod=755 /build/greet.wasm /greet.wasm
ENTRYPOINT [ "/greet.wasm" ]
# add the oci label to tell crun that this is a wasm workload.
# its not required for kubernetes, since the pod annotaion is used.
# its here for compeletness sake, in case you want to run the image with
# something like podman
LABEL module.wasm.image/variant=compat
