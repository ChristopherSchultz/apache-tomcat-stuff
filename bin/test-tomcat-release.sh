#!/bin/sh

TOMCAT_VERSION=
RELEASE_TYPE=archive
CLEAN=false
for arg in "$@" ; do
  case $arg in
    -c) CLEAN=true
        shift
        ;;

    -d) RELEASE_TYPE=dev
        shift
        ;;

    -h|--help) echo "Usage: $0 [-c] [-d] <version>"
        echo
        echo "  -c Clean-up any existing apache-tomcat-[version] files and re-download them."
        echo "  -d Download a development / release-candidate version for testing."
        echo
        echo "Example: $0 8.5.98"
        exit 0
        ;;

     *) break
        ;;
  esac
done

if [ "" = "$1" ] ; then
  >&2 echo "Usage: $0 [-c] [-d] <version>"
  >&2 echo
  >&2 echo "  -c Clean-up any existing apache-tomcat-[version] files and re-download them."
  >&2 echo "  -d Download a development / release-candidate version for testing."
  >&2 echo
  >&2 echo "Example: $0 8.5.88"
  exit 1
fi

TOMCAT_VERSION=${1}
TOMCAT_MAJOR_VERSION=$(echo ${TOMCAT_VERSION} | sed 's/\..*//')

if [ "${CLEAN}" = "true" ] ; then
  rm "apache-tomcat-${TOMCAT_VERSION}".*
fi

##
## Environment Setup and Validation
##

# Set default Java paths if not already set
export JAVA_8_HOME="${JAVA_8_HOME:-/usr/local/java-8}"
export JAVA_7_HOME="${JAVA_7_HOME:-/usr/local/java-7}"
export JAVA_6_HOME="${JAVA_6_HOME:-${HOME}/packages/jdk1.6.0_45}"

# Determine which Java version to use based on Tomcat version
# NOTE: Tomcat 7 needs JAVA_HOME to point to Java 6
if [ "7" = "$TOMCAT_MAJOR_VERSION" ] ; then
  JAVA_HOME="${JAVA_HOME:-$JAVA_6_HOME}"
  TEST_JAVA_HOME="${TEST_JAVA_HOME:-$JAVA_7_HOME}"
else
  JAVA_HOME="${JAVA_HOME:-$JAVA_7_HOME}"
fi
export TEST_JAVA_HOME="${TEST_JAVA_HOME:-$JAVA_HOME}"
export BUILD_JAVA_HOME="${BUILD_JAVA_HOME:-$JAVA_HOME}"
export BUILD_NATIVE_JAVA_HOME="${BUILD_NATIVE_JAVA_HOME:-$JAVA_HOME}"

# Validate BUILD_JAVA_HOME
if [ ! -d "${BUILD_JAVA_HOME}" ] || [ ! -x "${BUILD_JAVA_HOME}/bin/java" ] ; then
  >&2 echo "ERROR: BUILD_JAVA_HOME is not a valid Java installation: ${BUILD_JAVA_HOME}"
  >&2 echo "Please set BUILD_JAVA_HOME to a valid Java installation."
  exit 1
fi

# Validate TEST_JAVA_HOME
if [ ! -d "${TEST_JAVA_HOME}" ] || [ ! -x "${TEST_JAVA_HOME}/bin/java" ] ; then
  >&2 echo "ERROR: TEST_JAVA_HOME is not a valid Java installation: ${TEST_JAVA_HOME}"
  >&2 echo "Please set TEST_JAVA_HOME to a valid Java installation."
  exit 1
fi

# Validate BUILD_NATIVE_JAVA_HOME
if [ ! -d "${BUILD_NATIVE_JAVA_HOME}" ] || [ ! -x "${BUILD_NATIVE_JAVA_HOME}/bin/java" ] ; then
  >&2 echo "ERROR: BUILD_NATIVE_JAVA_HOME is not a valid Java installation: ${BUILD_NATIVE_JAVA_HOME}"
  >&2 echo "Please set BUILD_NATIVE_JAVA_HOME to a valid Java installation."
  exit 1
fi

# Validate ANT_HOME
if [ -z "${ANT_HOME}" ] || [ ! -d "${ANT_HOME}" ] || [ ! -x "${ANT_HOME}/bin/ant" ] ; then
  >&2 echo "ERROR: ANT_HOME is not a valid Apache Ant installation: ${ANT_HOME}"
  >&2 echo "Please set ANT_HOME to your Apache Ant installation directory."
  exit 1
fi

# Set up OpenSSL
# Set default only if not already set
export OPENSSL_HOME="${OPENSSL_HOME:-${HOME}/projects/apache/apache-tomcat/openssl-1.1.1/target}"

# If OPENSSL_HOME is set but doesn't exist, try to use system OpenSSL
if [ ! -z "${OPENSSL_HOME}" ] && [ "yes" != "${OPENSSL_HOME}" ] ; then
  if [ ! -d "${OPENSSL_HOME}" ] || [ ! -x "${OPENSSL_HOME}/bin/openssl" ] ; then
    >&2 echo "WARNING: OPENSSL_HOME does not exist or is invalid: ${OPENSSL_HOME}"
    >&2 echo "Attempting to use system-installed OpenSSL instead."
    OPENSSL_HOME=yes
  fi
fi

# Set up APR
APR_CONFIG=$( command -v apr-1-config )
if [ "" == "$APR_CONFIG" ] ; then
  if [ -n "${APR_HOME}" ] && [ -x "${APR_HOME}/bin/apr-1-config" ] ; then
    APR_CONFIG="${APR_HOME}/bin/apr-1-config"
  fi
fi
if [ "" == "$APR_CONFIG" ] ; then
  >&2 echo "ERROR: apr-1-config not found in PATH or APR_HOME."
  >&2 echo "Please install APR development tools or set APR_HOME appropriately."
  >&2 echo "(APR_HOME=${APR_HOME})"
  exit 1
fi

# Set up optional osslsigncode for Windows executable verification
OSSLSIGNCODE=$( command -v osslsigncode )
OSSLSIGNCODE_OPTS="${OSSLSIGNCODE_OPTS:--CAfile /etc/ssl/certs/ca-certificates.crt -untrusted /etc/ssl/certs/ca-certificates.crt}"

if [ "dev" = "${RELEASE_TYPE}" ] ; then
  BASE_URL="https://dist.apache.org/repos/dist/dev/tomcat/tomcat-${TOMCAT_MAJOR_VERSION}/v${TOMCAT_VERSION}"
else
  BASE_URL="https://archive.apache.org/dist/tomcat/tomcat-${TOMCAT_MAJOR_VERSION}/v${TOMCAT_VERSION}"
fi

BASE_BINARY_URL="${BASE_URL}/bin"
BASE_SOURCE_URL="${BASE_URL}/src"
BASE_FILE_NAME="apache-tomcat-${TOMCAT_VERSION}"
ZIPFILE="${BASE_FILE_NAME}.zip"
TARBALL="${BASE_FILE_NAME}.tar.gz"
INSTALLER="${BASE_FILE_NAME}.exe"
SRC_ZIPFILE="${BASE_FILE_NAME}-src.zip"
SRC_TARBALL="${BASE_FILE_NAME}-src.tar.gz"

BINARIES="${ZIPFILE} ${TARBALL} ${INSTALLER}"
SOURCES="${SRC_ZIPFILE} ${SRC_TARBALL}"

echo '* Environment'
build_java_version=`${BUILD_JAVA_HOME}/bin/java -version 2>&1`
test_java_version=`${TEST_JAVA_HOME}/bin/java -version 2>&1`
if [ "x" != "x${JAVA_FFM_HOME}" ] ; then
  ffm_java_version=$( ${JAVA_FFM_HOME}/bin/java -version 2>&1 )
else
  ffm_java_version=
fi
ant_version=`"${ANT_HOME}/bin/ant" -version`
echo '*  Java (build):   ' $build_java_version
if [ "x" != "x${ffm_java_version}" ] ; then
  echo '*  Java (ffm):     ' $ffm_java_version
fi
echo '*  Java (test):    ' $test_java_version
echo '*  Ant:            ' $ant_version
echo '*  OS:             ' `uname -mrs`
echo '*  cc:             ' `cc --version | head -n 1`
echo '*  make:           ' `make --version | head -n 1`
if [ "yes" = "${OPENSSL_HOME}" ] ; then
  echo '*  OpenSSL:        ' `openssl version`
else
  echo '*  OpenSSL:        ' `LD_LIBRARY_PATH="${OPENSSL_HOME}/lib" "${OPENSSL_HOME}"/bin/openssl version`
fi
echo '*  APR:            ' `${APR_CONFIG} --version`
echo '*'

build_java_version_number=$( echo "$build_java_version" | grep -i version | sed -e 's/[^"]*"//' -e 's/".*//' )
if [ "0" != $( expr "$build_java_version_number" : "^1\." ) ] ; then
  # This is "Java 1.x" and we really only care about x
  build_java_version_number=$( echo $build_java_version_number | sed -e 's/^1\.//' )
fi
if [ "0" != $( expr "$build_java_version_number" : ".*\..*" ) ] ; then
  # There are point-numbers to be removed
  build_java_version_number=$( echo $build_java_version_number | sed -e 's/\..*//' )
fi

# Get rid of anything that isn't a number (e.g. -ea)
build_java_version_number=$( echo $build_java_version_number | sed -e 's/[^0-9]//g' )

#if [ ! -f KEYS ] ; then
  # Fetch KEYS file
  echo "Downloading KEYS from ${BASE_URL}/KEYS..."
  curl -\#O "${BASE_URL}/KEYS"

  echo "Building local keyring..."
  gpg --import --no-default-keyring --primary-keyring ./apache-keys < KEYS > /dev/null 2>&1
#fi

for binary in ${BINARIES} ; do

  if [ ! -f "${binary}" ] ; then
    echo "Downloading ${BASE_BINARY_URL}/${binary}..."
    curl -f -\#O "${BASE_BINARY_URL}/${binary}" 2>&1
    if [ "0" != "$?" ] ; then
      1>&2 echo Failed to download ${BASE_BINARY_URL}/${binary}
      1>&2 echo
      if [ "dev" = "${RELEASE_TYPE}" ] ; then
        1>&2 echo "Perhaps you should not use the -d (development) switch for an already-released version?"
      else
        1>&2 echo "Perhaps you need to specify -d (development) to download a release for voting?"
      fi

      exit 1
    fi
    curl -f -\#O "${BASE_BINARY_URL}/${binary}.asc" 2>&1
    if [ "0" != "$?" ] ; then
      1>&2 echo Failed to download ${BASE_BINARY_URL}/${binary}.asc

      exit 1
    fi
    curl -f -\#O "${BASE_BINARY_URL}/${binary}.sha512" 2>&1
    if [ "0" != "$?" ] ; then
      1>&2 echo Failed to download ${BASE_BINARY_URL}/${binary}.sha512

      exit 1
    fi
  fi

  # Check SHA-2 sum
  shasum -a 512 --status -bc ${binary}.sha512 > /dev/null 2>&1
  result=$?

  if [ "$result" = "0" ] ; then
    echo "* Valid SHA-512 signature for ${binary}"
  else
    echo "* !! Invalid SHA-512 signature for ${binary}"
#echo Ran command "\"shasum -a 512 --status -bc ${binary}.sha512 > /dev/null 2>&1\""
  fi

  # Check GPG Signatures
  #echo -n "GPG verify ($binary): "
  gpg --keyring ./apache-keys --no-default-keyring --trust-model always --verify ${binary}.asc ${binary} > /dev/null 2>&1
  result=$?

  if [ "$result" = "0" ] ; then
    echo "* Valid GPG signature for ${binary}"
  else
    echo "* !! Invalid GPG signature for ${binary}"
  fi
  if [ -n "${OSSLSIGNCODE}" ] ; then
    case $binary in
      *.exe)
        ver=$( ${OSSLSIGNCODE} verify ${OSSLSIGNCODE_OPTS} "$binary" )
        result=$?
        if [ 255 -eq $result ] ; then
          ver=$( ${OSSLSIGNCODE} verify "$binary" )
          result=$?
        fi
        echo $ver | grep -q 'Subject:.*Apache ' > /dev/null
        result=$?
        if [ 0 -eq ${result} ]; then
          echo "* Valid Windows Digital Signature for ${binary}"
        else
          echo "* !! Invalid Windows Digital Signature for ${binary}"
        fi
      ;;
    esac
  fi
done

# Check to make sure tarball and zip contain the same files.
rm -rf zip tarball
mkdir zip
mkdir tarball
unzip -qd zip "${ZIPFILE}"
tar xz --directory "tarball" -f "${TARBALL}"

diff --strip-trailing-cr -qr zip tarball

result=$?

for source in ${SOURCES} ; do

  if [ ! -f "${source}" ] ; then
    echo "Downloading ${source}..."
    curl -f -\#O "${BASE_SOURCE_URL}/${source}" 2>&1
    if [ "0" != "$?" ] ; then
      1>&2 echo Failed to download ${BASE_SOURCE_URL}/${source}

      exit 1
    fi
    curl -f -\#O "${BASE_SOURCE_URL}/${source}.asc" 2>&1
    if [ "0" != "$?" ] ; then
      1>&2 echo Failed to download ${BASE_SOURCE_URL}/${source}.asc

      exit 1
    fi
    curl -f -\#O "${BASE_SOURCE_URL}/${source}.sha512" 2>&1
    if [ "0" != "$?" ] ; then
      1>&2 echo Failed to download ${BASE_SOURCE_URL}/${source}.sha256

      exit 1
    fi
  fi

  # Check SHA-2 sum
  shasum -a 512 --status -c ${source}.sha512 > /dev/null 2>&1
  result=$?

  if [ "$result" = "0" ] ; then
    echo "* Valid SHA512 signature for $source"
  else
    echo "* !! Invalid SHA512 signature for $source"
  fi

  # Check GPG Signatures
  #echo -n "GPG verify ($source): "
  gpg --keyring ./apache-keys --verify ${source}.asc ${source} > /dev/null 2>&1
  result=$?

  if [ "$result" = "0" ] ; then
    echo "* Valid GPG signature for ${source}"
  else
    echo "* !! Invalid GPG signature for ${source}"
  fi
done

/bin/echo '*'

/bin/echo -n "* Binary Zip and tarball: "
if [ "$result" = "0" ] ; then
  echo Same
else
  echo !! NOT SAME
fi

# Check to make sure source tarball and zip contain the same files.
rm -rf zip tarball
mkdir zip
mkdir tarball
unzip -qd "zip" "${SRC_ZIPFILE}"
tar xz --directory "tarball" -f "${SRC_TARBALL}"

diff --strip-trailing-cr -qr zip tarball

result=$?

/bin/echo -n "* Source Zip and tarball: "
if [ "$result" = "0" ] ; then
  echo Same
else
  echo !! NOT SAME
fi

echo '*'

# Leave the source tarball in place
rm -rf zip

## Build some stuff

#exit

# Prepare for build...
export ANT_OPTS="-Xmx512M"
export JAVA_OPTS="-Xmx512M"
BASE_DIR="`pwd`/tarball"
BASE_SOURCE_DIR="${BASE_DIR}/${BASE_FILE_NAME}-src"
cat <<ENDEND > "${BASE_SOURCE_DIR}/build.properties"
base.path=${BASE_DIR}/downloads
execute.validate=true
java.7.home=${JAVA_7_HOME}
nsis.tool=makensis
# TODO: This is specifically for MacOS
openssl.ffm.1=-Dorg.apache.tomcat.util.openssl.USE_SYSTEM_LOAD_LIBRARY=true
openssl.ffm.2=-Dorg.apache.tomcat.util.openssl.LIBRARY_NAME=ssl
java-ffm.home=${JAVA_FFM_HOME}
ENDEND

# Disable 'opens' on older Java versions.
if [ "$build_java_version_number" -lt "9" ] ; then
  echo "Suppressing 'opens' due to older Java version $build_java_version_number"
  cat <<ENDEND >> "${BASE_SOURCE_DIR}/build.properties"
opens.javalang=-Dnop
opens.javaio=-Dnop
opens.sunrmi=-Dnop
opens.javautil=-Dnop
opens.javautilconcurrent=-Dnop
ENDEND
fi

if [ "yes" != "${OPENSSL_HOME}" ] ; then
  echo "Suppressing IDEA tests via OpenSSL"
  cat <<ENDEND >> "${BASE_SOURCE_DIR}/build.properties"
test.openssl.unimplemeneted=IDEA
test.openssl.loc=${OPENSSL_HOME}/bin/openssl
ENDEND
fi

# Set test.apr.loc to point to where we built tcnative (unless SKIP_TCNATIVE_BUILD is set)
if [ -z "${SKIP_TCNATIVE_BUILD}" ] ; then
  cat <<ENDEND >> "${BASE_SOURCE_DIR}/build.properties"
test.apr.loc=${BASE_SOURCE_DIR}/output/build/bin/native
ENDEND
fi

echo "Downloading stuff..."
echo JAVA_HOME=$BUILD_JAVA_HOME "${ANT_HOME}/bin/ant" -f "${BASE_SOURCE_DIR}/build.xml" download-compile download-test-compile download-dist
JAVA_HOME=$BUILD_JAVA_HOME "${ANT_HOME}/bin/ant" -f "${BASE_SOURCE_DIR}/build.xml" download-compile download-test-compile download-dist

result=$?
echo "* Building dependencies returned: $result"

if [ "0" != "$result" ] ; then
  echo "* Dependencies failed to build. Quitting."
  exit
fi

echo "Building Tomcat..."
echo "Performing release build minus signatures, which should not be necessary."

JAVA_HOME=$BUILD_JAVA_HOME "${ANT_HOME}/bin/ant" -f "${BASE_SOURCE_DIR}/build.xml" -Dgpg.exec.available=false release

result=$?
if [ "0" != "$result" ] ; then
  echo "* !! Tomcat failed to build (result=$result). Quitting"
  exit
else
  echo "* Tomcat builds cleanly"
fi

if [ -z "${SKIP_TCNATIVE_BUILD}" ] ; then
  echo Building tcnative...
  mkdir -p "${BASE_SOURCE_DIR}/output/build/bin/native"

  tar xz --directory "${BASE_SOURCE_DIR}/output/build/bin/native" -f "${BASE_DIR}/downloads/tomcat-native"*"/tomcat-native"*".tar.gz"

  if [ "0" != "$?" ] ; then
    echo "* Failed to unpack tcnative. Quitting."
    exit
  fi

  if [ -d "${BASE_SOURCE_DIR}/output/build/bin/native/tomcat-native-"*/native ] ; then
    TCNATIVE_SOURCE_DIR=$(echo "${BASE_SOURCE_DIR}/output/build/bin/native/tomcat-native-"*/native)
  elif [ -d "${BASE_SOURCE_DIR}/output/build/bin/native/tomcat-native-"*/jni/native ] ; then
    TCNATIVE_SOURCE_DIR=$(echo "${BASE_SOURCE_DIR}/output/build/bin/native/tomcat-native-"*/jni/native)
  else
    echo "* !! Cannot find tomcat-native 'native' directory under " "${BASE_SOURCE_DIR}/output/build/bin/native/tomcat-native-"*
    echo Quitting
    exit
  fi
  OWD=`pwd`

  cd "${TCNATIVE_SOURCE_DIR}"

  echo "Building tcnative with OpenSSL ${OPENSSL_HOME}"
  if [ "yes" = "${OPENSSL_HOME}" ] ; then
    # Use system OpenSSL - let configure auto-detect it
    ./configure --with-apr=${APR_CONFIG} --with-java-home="${TEST_JAVA_HOME}" --exec-prefix=NONE
  else
    # Use specified OpenSSL installation
    ./configure --with-apr=${APR_CONFIG} --with-ssl="${OPENSSL_HOME}" --with-java-home="${TEST_JAVA_HOME}" --exec-prefix=NONE
  fi
  # /usr/lib/jvm/java-6-sun/

  result=$?

  if [ "0" != "$result" ] ; then
    echo "* !! tcnative configure returned non-zero result ($result). Quitting."
    exit
  fi

  cd "${OWD}"

  make -C "${TCNATIVE_SOURCE_DIR}"

  result=$?

  if [ "0" != "$result" ] ; then
    echo "* !! tcnative make returned non-zero result ($result). Quitting."
    exit
  else
    echo "* tcnative builds cleanly"
  fi

  cp -aR "${TCNATIVE_SOURCE_DIR}/.libs/"* "${BASE_SOURCE_DIR}/output/build/bin/native"
  if [ "yes" != "${OPENSSL_HOME}" ] ; then
    cp -aR "${OPENSSL_HOME}/lib/"* "${BASE_SOURCE_DIR}/output/build/bin/native"
  fi
fi

#echo NOT RUNNING UNIT TESTS
#exit

CAFFEINATE=$( command -v caffeinate )

echo Running all tests...
JAVA_HOME=$TEST_JAVA_HOME $CAFFEINATE "${ANT_HOME}/bin/ant" -f "${BASE_SOURCE_DIR}/build.xml" -Dexecute.validate=false test

grep "\(Failures\|Errors\): [^0]" "${BASE_SOURCE_DIR}/output/build/logs/"TEST*.txt
result=$?
if [ "$result" = "0" -o "$result" = "2" ] ; then
  junit=fail
else
  junit=pass
fi

if [ "$junit" = "pass" ] ; then
  echo "* Junit Tests: PASSED"
else
  echo "* Junit Tests: FAILED"
  echo "*"
  echo "* Tests that failed:"
  grep -l "\(Failures\|Errors\): [^0]" "${BASE_SOURCE_DIR}/output/build/logs/"TEST*.txt | sed -e "s#${BASE_SOURCE_DIR}/output/build/logs/TEST-#* #"
fi

