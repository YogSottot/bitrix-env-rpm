#/bin/bash
PROGNAME=$(basename $0)
PROGPATH=$(dirname $0)
[[ -z $DEBUG ]] && DEBUG=0

. $PROGPATH/functions.sh || exit 1

IP_ADDRESS="${1}"
INT_NAME="${2}"

restart_network_daemon

/opt/webdir/bin/update_network.sh $INT_NAME

