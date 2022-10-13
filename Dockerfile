
# x265 release is over 1 years old and master branch has a lot of fixes and improvements, so we checkout commit so no hash is needed
# bump: x265 /X265_VERSION=([[:xdigit:]]+)/ gitrefs:https://bitbucket.org/multicoreware/x265_git.git|re:#^refs/heads/master$#|@commit
# bump: x265 after ./hashupdate Dockerfile X265 $LATEST
# bump: x265 link "Source diff $CURRENT..$LATEST" https://bitbucket.org/multicoreware/x265_git/branches/compare/$LATEST..$CURRENT#diff
ARG X265_VERSION=0b75c44c10e605fe9e9ebed58f04a46271131827
ARG X265_URL="https://bitbucket.org/multicoreware/x265_git/get/$X265_VERSION.tar.bz2"
ARG X265_SHA256=8aaf96bae0025c3678c3c04cf2e645af4ae0acb5520c890b80474e96b868f545

# bump: alpine /FROM alpine:([\d.]+)/ docker:alpine|^3
# bump: alpine link "Release notes" https://alpinelinux.org/posts/Alpine-$LATEST-released.html
FROM alpine:3.16.2 AS base

FROM base AS download
ARG X265_URL
ARG X265_SHA256
ARG WGET_OPTS="--retry-on-host-error --retry-on-http-error=429,500,502,503 -nv"
WORKDIR /tmp
RUN \
  apk add --no-cache --virtual download \
    coreutils wget tar && \
  wget $WGET_OPTS -O x265_git.tar.bz2 "$X265_URL" && \
  echo "$X265_SHA256  x265_git.tar.bz2" | sha256sum --status -c - && \
  mkdir x265 && \
  tar xf x265_git.tar.bz2 -C x265 --strip-components=1 && \
  rm x265_git.tar.bz2 && \
  apk del download

FROM base AS build 
COPY --from=download /tmp/x265/ /tmp/x265/
WORKDIR /tmp/x265/build/linux
ARG CXXFLAGS="-O3 -s -static-libgcc -fno-strict-overflow -fstack-protector-all -fPIC"
# -w-macro-params-legacy to not log lots of asm warnings
# https://bitbucket.org/multicoreware/x265_git/issues/559/warnings-when-assembling-with-nasm-215
# TODO: remove 'sed' hack when upstream (x265) fixes the issue and adds '-DPIC' to ARM_ARGS
# https://bitbucket.org/multicoreware/x265_git/issues/619/missing-dpic-for-arm-causes-link-error-on
# CMAKEFLAGS issue
# https://bitbucket.org/multicoreware/x265_git/issues/620/support-passing-cmake-flags-to-multilibs
RUN \
  apk add --no-cache --virtual build \
    build-base cmake git numactl-dev && \
  sed -i '/^cmake / s/$/ -G "Unix Makefiles" ${CMAKEFLAGS}/' ./multilib.sh && \
  sed -i 's/ -DENABLE_SHARED=OFF//g' ./multilib.sh && \
  sed -i 's/set(ARM_ARGS -fPIC -flax-vector-conversions)/set(ARM_ARGS -DPIC -fPIC -flax-vector-conversions)/' ../../source/CMakeLists.txt && \
  MAKEFLAGS="-j$(nproc)" \
  CMAKEFLAGS="-DENABLE_SHARED=OFF -DCMAKE_VERBOSE_MAKEFILE=ON -DENABLE_AGGRESSIVE_CHECKS=ON -DCMAKE_ASM_NASM_FLAGS=-w-macro-params-legacy -DENABLE_NASM=ON -DCMAKE_BUILD_TYPE=Release" \
  ./multilib.sh && \
  make -C 8bit -j$(nproc) install && \
  apk del build

FROM scratch
ARG X265_VERSION
COPY --from=build /usr/local/lib/pkgconfig/x265.pc /usr/local/lib/pkgconfig/x265.pc
COPY --from=build /usr/local/lib/libx265.a /usr/local/lib/libx265.a
COPY --from=build /usr/local/include/x265*.h /usr/local/include/
