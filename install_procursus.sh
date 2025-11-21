#!/usr/bin/env bash
set -eu

DARWIN_VERSION=`uname -r | cut -d'.' -f1 | tr -d '\n'`
MIRROR='https://apt.procurs.us'
SUITES='big_sur'
COMPONENTS='main'

procursus_bootstrapped=`if [[ -e '/opt/procursus/.procursus_strapped' ]]; then echo 'true'; else echo 'false'; fi`

if (( DARWIN_VERSION < 20 )); then
	>&2 echo 'This action only works on runners with macOS>=11'
	exit 1
fi

if [[ x"${procursus_bootstrapped}" ==  x"false" ]]; then
  curl -L ${MIRROR}/bootstraps/${SUITES}/bootstrap-darwin-amd64.tar.zst | zstdcat - | sudo tar -xpkf - -C / || :
fi

PROCURSUS_PATHS=("/opt/procursus/games" "/opt/procursus/sbin" "/opt/procursus/bin" "/opt/procursus/local/sbin" "/opt/procursus/local/bin")
for i in "${PROCURSUS_PATHS[@]}";
do
	case ":$PATH:" in
		*:$i:*) echo "$i is already in PATH, not adding";;
		*) PATH="$i:${PATH}";;
	esac
done
export PATH

case ":${CPATH:-""}:" in
	*:/opt/procursus/include:*) echo "/opt/procursus/include already in CPATH, not adding";;
	*) CPATH=${CPATH:-""}:/opt/procursus/include;;
esac
export CPATH
echo $CPATH

case ":${LIBRARY_PATH:-""}:" in
	*:/opt/procursus/lib:*) echo "/opt/procursus/lib already in LIBRARY_PATH, not adding";;
	*) LIBRARY_PATH=${LIBRARY_PATH:-""}:/opt/procursus/lib;;
esac
export LIBRARY_PATH
echo ${LIBRARY_PATH}

if [[ x"${procursus_bootstrapped}" ==  x"false" ]]; then
  # Taken from Procursus' apt.postinst
  set -e
  getHiddenUserUid()
  {
    local __UIDS=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -ugr)
    local __NewUID
    for __NewUID in $__UIDS
    do
        if [[ $__NewUID -lt 499 ]] ; then
            break;
        fi
    done
    echo $((__NewUID+1))
  }

  if ! id _apt &>/dev/null; then
    # add unprivileged user for the apt methods
    sudo dscl . -create /Users/_apt UserShell /usr/bin/false
    sudo dscl . -create /Users/_apt NSFHomeDirectory /var/empty
    sudo dscl . -create /Users/_apt PrimaryGroupID -1
    sudo dscl . -create /Users/_apt UniqueID $(getHiddenUserUid)
    sudo dscl . -create /Users/_apt RealName "APT Sandbox User"
  else
    echo "APT Sandbox User already exists, not creating"
  fi

  echo -e "Types: deb\nURIs: ${MIRROR}\nSuites: ${SUITES}\nComponents: ${COMPONENTS}\n" | sudo tee /opt/procursus/etc/apt/sources.list.d/procursus.sources
  sudo apt-get -y update
  sudo apt-get -y --allow-downgrades -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" dist-upgrade || :
fi

sudo apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" ldid findutils sed coreutils trustcache make

