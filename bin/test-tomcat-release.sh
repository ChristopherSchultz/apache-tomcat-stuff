#!/bin/sh

export JAVA_8_HOME="${JAVA_8_HOME:-/usr/local/java-8}"
export JAVA_7_HOME="${JAVA_7_HOME:-/usr/local/java-7}"
export JAVA_6_HOME="${JAVA_6_HOME:-${HOME}/packages/jdk1.6.0_45}"
export OPENSSL_HOME="${OPENSSL_HOME:-${HOME}/projects/apache/apache-tomcat/openssl-1.1.1/target}"
OSSLSIGNCODE=$( command -v osslsigncode )

TOMCAT_VERSION=${TOMCAT_VERSION-8.5.69}
TOMCAT_MAJOR_VERSION=$(echo ${TOMCAT_VERSION} | sed 's/\..*//')

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

BASE_URL="https://dist.apache.org/repos/dist/dev/tomcat/tomcat-${TOMCAT_MAJOR_VERSION}/v${TOMCAT_VERSION}"
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
echo '*  Java (build):    ' $build_java_version
echo '*  Java (test):    ' $test_java_version
echo '*  OS:      ' `uname -mrs`
echo '*  cc:      ' `cc --version | head -n 1`
echo '*  make:    ' `make --version | head -n 1`
if [ -z "${OPENSSL_HOME}" ] ; then
  echo '*  OpenSSL: ' `openssl version`
  # Set OPENSSL_HOME=yes to use system-installed openssl version
  OPENSSL_HOME=yes
else
  echo '*  OpenSSL: ' `LD_LIBRARY_PATH="${OPENSSL_HOME}/lib" "${OPENSSL_HOME}"/bin/openssl version`
fi
echo '*  APR:     ' `apr-1-config --version`
echo '*'

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
    curl -\#O "${BASE_BINARY_URL}/${binary}"
    curl -\#O "${BASE_BINARY_URL}/${binary}.asc"
    curl -\#O "${BASE_BINARY_URL}/${binary}.sha512"
  fi

  # Check SHA-2 sum
  shasum -a 512 --status -bc ${binary}.sha512 > /dev/null 2>&1
  result=$?

  if [ "$result" = "0" ] ; then
    echo "* Valid SHA-512 signature for ${binary}"
  else
    echo "* !! Invalid SHA-512 signature for ${binary}"
  fi

  # Check GPG Signatures
  #echo -n "GPG verify ($binary): "
  gpg --keyring ./apache-keys --no-default-keyring --verify ${binary}.asc ${binary} > /dev/null 2>&1
  result=$?

  if [ "$result" = "0" ] ; then
    echo "* Valid GPG signature for ${binary}"
  else
    echo "* !! Invalid GPG signature for ${binary}"
  fi
  if [ -n "${OSSLSIGNCODE}" ] ; then
    case $binary in
      *.exe)
        ver=$( ${OSSLSIGNCODE} verify -CAfile /dev/null "$binary" )
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
    curl -\#O "${BASE_SOURCE_URL}/${source}"
    curl -\#O "${BASE_SOURCE_URL}/${source}.asc"
    curl -\#O "${BASE_SOURCE_URL}/${source}.sha512"
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

echo '*'

echo -n "* Binary Zip and tarball: "
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

echo -n "* Source Zip and tarball: "
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
execute.validate=true
java.7.home=${JAVA_7_HOME}
execute.validate=false
ENDEND

if [ "yes" != "${OPENSSL_HOME}" ] ; then
  /bin/echo -e "\ntest.openssl.loc=${OPENSSL_HOME}/bin/openssl" >> "${BASE_SOURCE_DIR}/build.properties"
fi
JAVA_HOME=$BUILD_JAVA_HOME ant -f "${BASE_SOURCE_DIR}/build.xml" download-compile download-test-compile download-dist

result=$?
echo "* Building dependencies returned: $result"

if [ "0" != "$result" ] ; then
  echo "* Dependencies failed to build. Quitting."
  exit
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
  ./configure --with-apr=/usr/bin --with-ssl="${OPENSSL_HOME}" --with-java-home="${TEST_JAVA_HOME}" --exec-prefix=NONE
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

echo "Building Tomcat..."
JAVA_HOME=$BUILD_JAVA_HOME ant -f "${BASE_SOURCE_DIR}/build.xml" deploy

result=$?
if [ "0" != "$result" ] ; then
  echo "* !! Tomcat failed to build (result=$result). Quitting"
  exit
else
  echo "* Tomcat builds cleanly"
fi

#echo NOT RUNNING UNIT TESTS
#exit

echo Running all tests...
JAVA_HOME=$TEST_JAVA_HOME ant -f "${BASE_SOURCE_DIR}/build.xml" test

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

