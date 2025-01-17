#!/bin/bash
#
# Build MariaDB .deb packages for test and release at mariadb.org
#

# Exit immediately on any error
set -e

# On Buildbot, don't run the mysql-test-run test suite as part of build.
# It takes a lot of time, and we will do a better test anyway in
# Buildbot, running the test suite from installed .debs on a clean VM.
export DEB_BUILD_OPTIONS="nocheck"

# Don't include test suite package to make the build time shorter
sed '/Package: mariadb-test-data/,/^$/d' -i debian/control
sed '/Package: mariadb-test/,/^$/d' -i debian/control

export MYSQL_COMPILER_LAUNCHER=ccache

# Don't include TokuDB since it's deprecated
sed '/Package: mariadb-plugin-tokudb/,/^$/d' -i debian/control
sed 's|-DDEB|-DPLUGIN_TOKUDB=NO -DDEB|' -i debian/rules

# Look up distro-version specific stuff
#
# Always keep the actual packaging as up-to-date as possible following the latest
# Debian policy and targeting Debian Sid. Then case-by-case run in autobake-deb.sh
# tests for backwards compatibility and strip away parts on older builders.

LSBID="$(lsb_release -si  | tr '[:upper:]' '[:lower:]')"
LSBVERSION="$(lsb_release -sr | sed -e "s#\.##g")"
LSBNAME="$(lsb_release -sc)"

if [ -z "${LSBID}" ]
then
    LSBID="unknown"
fi

case "${LSBNAME}" in
  stretch)
    # MDEV-28022 libzstd-dev-1.1.3 minimum version
    sed -i -e '/libzstd-dev/d' debian/control
    ;;
esac

# If iproute2 is not available (before Debian Jessie and Ubuntu Trusty)
# fall back to the old iproute package.
if ! apt-cache madison iproute2 | grep 'iproute2 *|' >/dev/null 2>&1
then
  sed 's/iproute2/iproute/' -i debian/control
fi

# If libcrack2 (>= 2.9.0) is not available (before Debian Jessie and Ubuntu Trusty)
# clean away the cracklib stanzas so the package can build without them.
if ! apt-cache madison libcrack2-dev | grep 'libcrack2-dev *| *2\.9' >/dev/null 2>&1
then
  sed '/libcrack2-dev/d' -i debian/control
  sed '/Package: mariadb-plugin-cracklib/,/^$/d' -i debian/control
fi

# If libpcre3-dev (>= 2:8.35-3.2~) is not available (before Debian Jessie or Ubuntu Wily)
# clean away the PCRE3 stanzas so the package can build without them.
# Update check when version 2:8.40 or newer is available.
if ! apt-cache madison libpcre3-dev | grep 'libpcre3-dev *| *2:8\.3[2-9]' >/dev/null 2>&1
then
  sed '/libpcre3-dev/d' -i debian/control
fi

# If libsystemd-dev is not available (before Debian Jessie or Ubuntu Wily)
# clean away the systemd stanzas so the package can build without them.
if ! apt-cache madison libsystemd-dev | grep 'libsystemd-dev' >/dev/null 2>&1
then
  sed '/libsystemd-dev/d' -i debian/control
  sed 's/ --with systemd//' -i debian/rules
  sed '/systemd/d' -i debian/rules
  sed '/\.service/d' -i debian/rules
  sed '/galera_new_cluster/d' -i debian/mariadb-server-10.4.install
  sed '/galera_recovery/d' -i debian/mariadb-server-10.4.install
  sed '/mariadb-service-convert/d' -i debian/mariadb-server-10.4.install
fi

# Don't build rocksdb package on x86 32 bit.
if [[ $(arch) =~ i[346]86 ]]
then
  sed '/Package: mariadb-plugin-rocksdb/,/^$/d' -i debian/control
fi

## Skip TokuDB if arch is not amd64
if [[ ! $(dpkg-architecture -qDEB_BUILD_ARCH) =~ amd64 ]]
then
  sed '/Package: mariadb-plugin-tokudb/,/^$/d' -i debian/control
fi

# Always remove aws plugin, see -DNOT_FOR_DISTRIBUTION in CMakeLists.txt
sed '/Package: mariadb-plugin-aws-key-management-10.4/,/^$/d' -i debian/control

# Don't build cassandra package if thrift is not installed
if [[ ! -f /usr/local/include/thrift/Thrift.h && ! -f /usr/include/thrift/Thrift.h ]]
then
  sed '/Package: mariadb-plugin-cassandra/,/^$/d' -i debian/control
fi

# Adjust changelog, add new version
echo "Incrementing changelog and starting build scripts"

# Find major.minor version
source ./VERSION
UPSTREAM="${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}.${MYSQL_VERSION_PATCH}${MYSQL_VERSION_EXTRA}"
PATCHLEVEL="+maria"
LOGSTRING="MariaDB build"
EPOCH="1:"
VERSION="${EPOCH}${UPSTREAM}${PATCHLEVEL}~${LSBID:0:3}${LSBVERSION}"

dch -b -D ${LSBNAME} -v "${VERSION}" "Automatic build with ${LOGSTRING}."

echo "Creating package version ${VERSION} ... "

# Use -b to build binary only packages as there is no need to
# waste time on generating the source package.
BUILDPACKAGE_FLAGS="-b"

# Build the package
# Pass -I so that .git and other unnecessary temporary and source control files
# will be ignored by dpkg-source when creating the tar.gz source package.
fakeroot dpkg-buildpackage -us -uc -I $BUILDPACKAGE_FLAGS -j$(nproc)

# If the step above fails due to missing dependencies, you can manually run
#   sudo mk-build-deps debian/control -r -i

echo "List package contents ..."
cd ..
for package in `ls *.deb`
do
  echo $package | cut -d '_' -f 1
  dpkg-deb -c $package | awk '{print $1 " " $2 " " $6}' | sort -k 3
  echo "------------------------------------------------"
done

echo "Build complete"
