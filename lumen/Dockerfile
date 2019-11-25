#===- lumen/Dockerfile ---------------------------------------------------===//
#
# Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
#===----------------------------------------------------------------------===//
# Stage 1. Check out LLVM source code and run the build.
FROM launcher.gcr.io/google/debian9:latest AS builder
LABEL maintainer "Lumen Developers"

# Install build dependencies of llvm.
# First, Update the apt's source list and include the sources of the packages.
RUN grep deb /etc/apt/sources.list | \
    sed 's/^deb/deb-src /g' >> /etc/apt/sources.list

# Install compiler, python and subversion.
# LLDB doesn't build with Swig 3.0.9-10
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        gnupg \
        build-essential \
        libedit-dev \
        libxml2-dev \
        libncurses5-dev \
        python2.7-dev \
        file \
        python \
        wget \
        git \
        unzip && \
    wget "http://ftp.de.debian.org/debian/pool/main/s/swig/swig3.0_3.0.12-2.2_amd64.deb" && \
    wget "http://ftp.de.debian.org/debian/pool/main/s/swig/swig_3.0.12-2.2_amd64.deb" && \
    dpkg -i swig3.0_3.0.12-2.2_amd64.deb && \
    dpkg -i swig_3.0.12-2.2_amd64.deb && \
    rm -rf /var/lib/apt/lists/*

# Install a newer ninja release. It seems the older version in the debian repos
# randomly crashes when compiling llvm.
ENV NINJA_VERSION=1.9.0
RUN wget "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip" && \
    unzip ninja-linux.zip -d /usr/local/bin && \
    rm ninja-linux.zip

# Download, verify and install cmake version that can compile clang into /usr/local.
ENV CMAKE_VERSION=3.15.5
RUN mkdir /tmp/cmake-install && \
    cd /tmp/cmake-install && \
    wget "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz" && \
    tar -xzf cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz -C /usr/local --strip-components=1 && \
    cd / && rm -rf /tmp/cmake-install

# Checkout the source code.
RUN mkdir -p /tmp/sources && \
    git clone --depth=1 --single-branch https://github.com/lumen/llvm-project /tmp/sources

ADD utils/dist /tmp/scripts

# Run the stage1 build. This bootstraps the clang compiler.
ARG buildscript_args
RUN mkdir -p /tmp/build && \
    mkdir -p /tmp/install && \
    mkdir -p /tmp/dist && \
    /tmp/scripts/build-dist.sh \
        -stage 1 \
        -build-dir /tmp/build \
        -src-dir /tmp/sources \
        -install-dir /tmp/install \
        -dist-dir /tmp/dist \
        ${buildscript_args}

# Run the stage2 build. This builds the release compiler and tools.
# Results of the build will be available at /tmp/install/.
RUN /tmp/scripts/build-dist.sh \
        -stage 2 \
        -build-dir /tmp/build \
        -src-dir /tmp/sources \
        -install-dir /tmp/install \
        -dist-dir /tmp/dist \
        ${buildscript_args}

# Distribution image. Produces a scratch image with the release package
FROM scratch AS dist
COPY --from=builder /tmp/dist /opt/dist

# Stage 2. Produce a minimal release image with build results.
FROM launcher.gcr.io/google/debian9:latest AS release
LABEL maintainer "Lumen Developers"

# Install packages for minimal useful image.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libstdc++-4.9-dev \
        binutils && \
    rm -rf /var/lib/apt/lists/*
# Copy build results of stage 1 to /usr/local.
COPY --from=builder /tmp/install/ /usr/local/
ENTRYPOINT ["bash"]
