#!/usr/bin/bash
#
pushd /etc/php.d >/dev/null 2>&1
for file in *.ini; do
    is_good=$(grep extension $file | grep -c '\.so')
    if [[ $is_good -eq 0 ]]; then
        sed -i 's/extension\s*=\s*\(.\+\)/extension=\1.so/' $file
    fi
done
popd >/dev/null 2>&1
