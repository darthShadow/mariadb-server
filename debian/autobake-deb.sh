#!/bin/bash
#
# Build MariaDB .deb packages for test and release at mariadb.org
#
# Purpose of this script:
# Always keep the actual packaging as up-to-date as possible following the latest
# Debian policy and targeting Debian Sid. Then case-by-case run in autobake-deb.sh
# tests for backwards compatibility and strip away parts on older builders or
# specific build environments.

# Exit immediately on any error
set -e

# On Buildbot, don't run the mysql-test-run test suite as part of build.
# It takes a lot of time, and we will do a better test anyway in
# Buildbot, running the test suite from installed .debs on a clean VM.
export DEB_BUILD_OPTIONS="nocheck $DEB_BUILD_OPTIONS"

source ./VERSION

if [ -d storage/columnstore/columnstore/debian ]
then
  # ColumnStore is explicitly disabled in the native Debian build, so allow it
  # now when build is triggered by autobake-deb.sh (MariaDB.org) and when the
  # build is not running on Travis or Gitlab-CI
  sed '/-DPLUGIN_COLUMNSTORE=NO/d' -i debian/rules
  # Take the files and part of control from MCS directory
  if [ ! -f debian/mariadb-plugin-columnstore.install ]
  then
    cp -v storage/columnstore/columnstore/debian/mariadb-plugin-columnstore.* debian/
    echo >> debian/control
    cat storage/columnstore/columnstore/debian/control >> debian/control
  fi
fi

# Build optimizations
# Make the build less verbose
sed -i '/Add support for verbose builds/,/^$/d' debian/rules

# Don't include test suite package to make the build time shorter
sed '/Package: mariadb-test-data/,/^$/d' -i debian/control
sed '/Package: mariadb-test/,/^$/d' -i debian/control
sed '/Package: mariadb-plugin-tokudb/,/^$/d' -i debian/control
sed '/Package: mariadb-plugin-mroonga/,/^$/d' -i debian/control
sed '/Package: mariadb-plugin-spider/,/^$/d' -i debian/control
sed '/Package: mariadb-plugin-oqgraph/,/^$/d' -i debian/control
export MYSQL_COMPILER_LAUNCHER=ccache
sed 's|-DDEB|-DPLUGIN_TOKUDB=NO -DPLUGIN_MROONGA=NO -DPLUGIN_SPIDER=NO -DPLUGIN_OQGRAPH=NO -DPLUGIN_PERFSCHEMA=NO -DWITH_EMBEDDED_SERVER=OFF -DDEB|' -i debian/rules

# Look up distro-version specific stuff
#
# Always keep the actual packaging as up-to-date as possible following the latest
# Debian policy and targeting Debian Sid. Then case-by-case run in autobake-deb.sh
# tests for backwards compatibility and strip away parts on older builders.

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

# If libpcre2-dev (>= 10.34~) is not available (before Debian Jessie or Ubuntu Wily)
# clean away the PCRE2 stanzas so the package can build without them.
# Update check when version 10.40 or newer is available.
if ! apt-cache madison libpcre2-dev | grep 'libpcre2-dev *| *10\.3[4-9]' >/dev/null 2>&1
then
  sed '/libpcre2-dev/d' -i debian/control
fi

# If libsystemd-dev is not available (before Debian Jessie or Ubuntu Wily)
# clean away the systemd stanzas so the package can build without them.
if ! apt-cache madison libsystemd-dev | grep 'libsystemd-dev' >/dev/null 2>&1
then
  sed '/dh-systemd/d' -i debian/control
  sed '/libsystemd-dev/d' -i debian/control
  sed 's/ --with systemd//' -i debian/rules
  sed '/systemd/d' -i debian/rules
  sed '/\.service/d' -i debian/rules
  sed '/galera_new_cluster/d' -i debian/mariadb-server-10.6.install
  sed '/galera_recovery/d' -i debian/mariadb-server-10.6.install
  sed '/mariadb-service-convert/d' -i debian/mariadb-server-10.6.install
fi

# Don't build rocksdb package on x86 32 bit.
if [[ $(arch) =~ i[346]86 ]]
then
  sed '/Package: mariadb-plugin-rocksdb/,/^$/d' -i debian/control
fi

remove_rocksdb_tools()
{
  sed '/rocksdb-tools/d' -i debian/control
  sed '/sst_dump/d' -i debian/not-installed
  if ! grep -q sst_dump debian/mariadb-plugin-rocksdb.install
  then
    echo "usr/bin/sst_dump" >> debian/mariadb-plugin-rocksdb.install
  fi
}

replace_uring_with_aio()
{
  sed 's/liburing-dev/libaio-dev/g' -i debian/control
  sed -e '/-DIGNORE_AIO_CHECK=YES/d' \
      -e '/-DWITH_URING=yes/d' -i debian/rules
}

disable_pmem()
{
  sed '/libpmem-dev/d' -i debian/control
  sed '/-DWITH_PMEM=yes/d' -i debian/rules
}

architecture=$(dpkg-architecture -qDEB_BUILD_ARCH)

CODENAME="$(lsb_release -sc)"
case "${CODENAME}" in
  stretch)
    # MDEV-16525 libzstd-dev-1.1.3 minimum version
    sed -e '/libzstd-dev/d' \
        -e 's/libcurl4/libcurl3/g' -i debian/control
    remove_rocksdb_tools
    disable_pmem
    ;&
  buster)
    replace_uring_with_aio
    if [ ! "$architecture" = amd64 ]
    then
      disable_pmem
    fi
    ;&
  bullseye|bookworm)
    # mariadb-plugin-rocksdb in control is 4 arches covered by the distro rocksdb-tools
    # so no removal is necessary.
    if [[ ! "$architecture" =~ amd64|arm64|ppc64el ]]
    then
      disable_pmem
    fi
    if [[ ! "$architecture" =~ amd64|arm64|armel|armhf|i386|mips64el|mipsel|ppc64el|s390x ]]
    then
      replace_uring_with_aio
    fi
    ;&
  sid)
    # should always be empty here.
    # need to match here to avoid the default Error however
    ;;
    # UBUNTU
  trusty)
    remove_rocksdb_tools
    disable_pmem
    replace_uring_with_aio
    ;&
  bionic)
    remove_rocksdb_tools
    [ "$architecture" != amd64 ] && disable_pmem
    ;&
  focal)
    replace_uring_with_aio
    ;&
  impish|jammy)
    # mariadb-plugin-rocksdb s390x not supported by us (yet)
    # ubuntu doesn't support mips64el yet, so keep this just
    # in case something changes.
    if [[ ! "$architecture" =~ amd64|arm64|ppc64el|s390x ]]
    then
      remove_rocksdb_tools
    fi
    if [[ ! "$architecture" =~ amd64|arm64|ppc64el ]]
    then
      disable_pmem
    fi
    if [[ ! "$architecture" =~ amd64|arm64|armhf|ppc64el|s390x ]]
    then
      replace_uring_with_aio
    fi
    ;;
  *)
    echo "Error - unknown release codename $CODENAME" >&2
    exit 1
esac

if [ -n "${AUTOBAKE_PREP_CONTROL_RULES_ONLY:-}" ]
then
  exit 0
fi

# From Debian Stretch/Ubuntu Bionic onwards dh-systemd is just an empty
# transitional metapackage and the functionality was merged into debhelper.
# In Ubuntu Hirsute is was completely removed, so it can't be referenced anymore.
# Keep using it only on Debian Jessie and Ubuntu Xenial.
if apt-cache madison dh-systemd | grep 'dh-systemd' >/dev/null 2>&1
then
  sed 's/debhelper (>= 9.20160709~),/debhelper (>= 9), dh-systemd,/' -i debian/control
fi

# Adjust changelog, add new version
echo "Incrementing changelog and starting build scripts"

# Find major.minor version
UPSTREAM="${MYSQL_VERSION_MAJOR}.${MYSQL_VERSION_MINOR}.${MYSQL_VERSION_PATCH}${MYSQL_VERSION_EXTRA}"
PATCHLEVEL="+maria"
LOGSTRING="MariaDB build"
EPOCH="1:"
VERSION="${EPOCH}${UPSTREAM}${PATCHLEVEL}~${CODENAME}"

dch -b -D "${CODENAME}" -v "${VERSION}" "Automatic build with ${LOGSTRING}." --controlmaint

echo "Creating package version ${VERSION} ... "

# Use eatmydata is available to build faster with less I/O, skipping fsync()
# during the entire build process (safe because a build can always be restarted)
if which eatmydata > /dev/null
then
  BUILDPACKAGE_PREPEND=eatmydata
fi

dch -b -D ${CODENAME} -v "${EPOCH}${UPSTREAM}${PATCHLEVEL}~${CODENAME}" "Automatic build with ${LOGSTRING}."

echo "Creating package version ${EPOCH}${UPSTREAM}${PATCHLEVEL}~${CODENAME} ... "

# Use -b to build binary only packages as there is no need to
# waste time on generating the source package.
BUILDPACKAGE_FLAGS="-b"

# Build the package
# Pass -I so that .git and other unnecessary temporary and source control files
# will be ignored by dpkg-source when creating the tar.gz source package.
fakeroot $BUILDPACKAGE_PREPEND dpkg-buildpackage -us -uc -I $BUILDPACKAGE_FLAGS

# If the step above fails due to missing dependencies, you can manually run
#   sudo mk-build-deps debian/control -r -i

# Don't log package contents on Gitlab-CI to save time and log size
echo "List package contents ..."
cd ..
for package in *.deb
do
  echo "$package" | cut -d '_' -f 1
  dpkg-deb -c "$package" | awk '{print $1 " " $2 " " $6 " " $7 " " $8}' | sort -k 3
  echo "------------------------------------------------"
done

echo "Build complete"
