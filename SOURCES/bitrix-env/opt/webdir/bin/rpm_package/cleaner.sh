#!/usr/bin/bash
#
#set -x
#
export LANG=en_US.UTF-8
export PATH=/sbin:/bin:/usr/sbin:/usr/bin
export NOLOCALE=yes

PWD=$0

# clean root password file
ROOTPASSWORD=/root/ROOT_PASSWORD

is_changed=$(chage -l root | grep "Password expires" | grep "password must be changed" -c)
if [[ $is_changed -eq 0 ]]; then
    rm -f $ROOTPASSWORD

    # clean selfy
    ROOTBASH_PROFILE=/root/.bash_profile
    sed -i ":$PWD:d" $ROOTBASH_PROFILE

    # update logon screen
    /opt/webdir/bin/bx_motd > /etc/issue 2>/dev/null

    # delete
    # echo /opt/webdir/bin/rpm_package/cleaner.sh >> /root/.bash_profile
    sed -i '/\/opt\/webdir\/bin\/rpm_package\/cleaner\.sh/d' \
        /root/.bash_profile
fi
