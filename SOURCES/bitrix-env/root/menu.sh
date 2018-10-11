#!/bin/bash

. /opt/webdir/bin/bitrix_utils.sh || exit 1


get_os_type

if [[ $BITRIX_ENV_TYPE == "crm" ]]; then
    /opt/webdir/bin/pool_menu_crm.sh
else
    /opt/webdir/bin/pool_menu.sh
fi
