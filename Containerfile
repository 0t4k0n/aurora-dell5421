FROM scratch AS ctx
COPY build_files /build_files
COPY system_files /build_files/system_files
COPY cosign.pub /build_files/cosign.pub
FROM ghcr.io/ublue-os/aurora:stable
RUN --mount=type=bind,from=ctx,source=/build_files,target=/ctx,ro --mount=type=tmpfs,target=/tmp /usr/bin/bash /ctx/build.sh
RUN bootc container lint
