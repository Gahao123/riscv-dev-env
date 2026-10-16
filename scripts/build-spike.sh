#!/usr/bin/env bash
set -euo pipefail
mkdir -p /build/spike /build/spike-build /opt/spike/share
tar -xf /archives/spike-v1.1.0.tar.gz --strip-components=1 -C /build/spike
patch --batch --forward -d /build/spike -p1 < /recipe/patches/spike-gcc13-cstdint.patch
cd /build/spike-build
/build/spike/configure --prefix=/opt/spike
make -j"${BUILD_JOBS:-2}"
make install
cp /build/spike/LICENSE /opt/spike/share/LICENSE
printf '%s\n' 'v1.1.0' '530af85d83781a3dae31a4ace84a573ec255fefa' \
    'Compatibility backport: 0a7bb5403d0290cea8b2356179d92e4c61ffd51d (Julien Olivain)' \
    > /opt/spike/share/source-version.txt
rm -rf /build/spike /build/spike-build
