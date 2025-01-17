#!/usr/bin/env sh

# Shamelessly copied from https://github.com/technosophos/helm-template

PROJECT_NAME="helm-diff"
PROJECT_GH="databus23/$PROJECT_NAME"
export GREP_COLOR="never"

# Convert HELM_BIN and HELM_PLUGIN_DIR to unix if cygpath is
# available. This is the case when using MSYS2 or Cygwin
# on Windows where helm returns a Windows path but we
# need a Unix path

if type cygpath >/dev/null 2>&1; then
  HELM_BIN="$(cygpath -u "${HELM_BIN}")"
  HELM_PLUGIN_DIR="$(cygpath -u "${HELM_PLUGIN_DIR}")"
fi

[ -z "$HELM_BIN" ] && HELM_BIN=$(which helm)
HELM_MAJOR_VERSION=$("${HELM_BIN}" version --client --short | awk -F '.' '{print $1}')

HELM_HOME=$("${HELM_BIN}" home --debug=false)
[ -z "$HELM_HOME" ] && HELM_HOME=$(helm env | grep 'HELM_DATA_HOME' | cut -d '=' -f2 | tr -d '"')

mkdir -p "$HELM_HOME"

: ${HELM_PLUGIN_DIR:="$HELM_HOME/plugins/helm-diff"}

if [ "$SKIP_BIN_INSTALL" = "1" ]; then
  echo "Skipping binary install"
  exit
fi

# which mode is the common installer script running in
SCRIPT_MODE="install"
if [ "$1" = "-u" ]; then
  SCRIPT_MODE="update"
fi

# initArch discovers the architecture for this system.
initArch() {
  ARCH=$(uname -m)
  case $ARCH in
  armv5*) ARCH="armv5" ;;
  armv6*) ARCH="armv6" ;;
  armv7*) ARCH="armv7" ;;
  aarch64) ARCH="arm64" ;;
  x86) ARCH="386" ;;
  x86_64) ARCH="amd64" ;;
  i686) ARCH="386" ;;
  i386) ARCH="386" ;;
  esac
}

# initOS discovers the operating system for this system.
initOS() {
  OS=$(uname | tr '[:upper:]' '[:lower:]')

  case "$OS" in
  # Msys support
  msys*) OS='windows' ;;
  # Minimalist GNU for Windows
  mingw*) OS='windows' ;;
  darwin) OS='macos' ;;
  esac
}

# verifySupported checks that the os/arch combination is supported for
# binary builds.
verifySupported() {
  supported="linux-amd64\nlinux-arm64\nfreebsd-amd64\nmacos-amd64\nmacos-arm64\nwindows-amd64"
  if ! echo "${supported}" | grep -q "${OS}-${ARCH}"; then
    echo "No prebuild binary for ${OS}-${ARCH}."
    exit 1
  fi

  if ! type "curl" >/dev/null && ! type "wget" >/dev/null; then
    echo "Either curl or wget is required"
    exit 1
  fi
}

# getDownloadURL checks the latest available version.
getDownloadURL() {
  version=$(git -C "$HELM_PLUGIN_DIR" describe --tags --exact-match 2>/dev/null || :)
  if [ "$SCRIPT_MODE" = "install" -a -n "$version" ]; then
    DOWNLOAD_URL="https://github.com/$PROJECT_GH/releases/download/$version/helm-diff-$OS-$ARCH.tgz"
  else
    DOWNLOAD_URL="https://github.com/$PROJECT_GH/releases/latest/download/helm-diff-$OS-$ARCH.tgz"
  fi
}

# Temporary dir
mkTempDir() {
  HELM_TMP="$(mktemp -d -t "${PROJECT_NAME}-XXXXXX")"
}
rmTempDir() {
  if [ -d "${HELM_TMP:-/tmp/helm-diff-tmp}" ]; then
    rm -rf "${HELM_TMP:-/tmp/helm-diff-tmp}"
  fi
}

# downloadFile downloads the latest binary package and also the checksum
# for that binary.
downloadFile() {
  PLUGIN_TMP_FILE="${HELM_TMP}/${PROJECT_NAME}.tgz"
  echo "Downloading $DOWNLOAD_URL"
  if type "curl" >/dev/null; then
    curl -L "$DOWNLOAD_URL" -o "$PLUGIN_TMP_FILE"
  elif type "wget" >/dev/null; then
    wget -q -O "$PLUGIN_TMP_FILE" "$DOWNLOAD_URL"
  fi
}

# installFile verifies the SHA256 for the file, then unpacks and
# installs it.
installFile() {
  tar xvzf "$PLUGIN_TMP_FILE" -C "$HELM_TMP"
  HELM_TMP_BIN="$HELM_TMP/diff/bin/diff"
  echo "Preparing to install into ${HELM_PLUGIN_DIR}"
  mkdir -p "$HELM_PLUGIN_DIR/bin"
  cp "$HELM_TMP_BIN" "$HELM_PLUGIN_DIR/bin"
}

# exit_trap is executed if on exit (error or not).
exit_trap() {
  result=$?
  rmTempDir
  if [ "$result" != "0" ]; then
    echo "Failed to install $PROJECT_NAME"
    printf '\tFor support, go to https://github.com/databus23/helm-diff.\n'
  fi
  exit $result
}

# testVersion tests the installed client to make sure it is working.
testVersion() {
  set +e
  echo "$PROJECT_NAME installed into $HELM_PLUGIN_DIR/$PROJECT_NAME"
  "${HELM_PLUGIN_DIR}/bin/diff" -h
  set -e
}

# Execution

#Stop execution on any error
trap "exit_trap" EXIT
set -e
initArch
initOS
verifySupported
getDownloadURL
mkTempDir
downloadFile
installFile
testVersion
