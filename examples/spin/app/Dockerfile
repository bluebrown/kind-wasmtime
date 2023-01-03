FROM --platform=amd64 tinygo/tinygo:0.25.0 as build
RUN apt-get -y update
RUN apt-get -y install curl
RUN curl -fsSL https://github.com/fermyon/spin/releases/download/v0.7.1/spin-v0.7.1-linux-amd64.tar.gz | tar -C /usr/local/bin -xzf - spin
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN spin build

FROM --platform=wasi/wasm32 scratch
COPY --from=build --chmod=755 /build/spin.toml /build/main.wasm  /
