#!/bin/bash

test -d "/etc/bx_cluster/nodes" && { rm -fr /etc/bx_cluster/nodes ; mkdir -p /etc/bx_cluster/nodes ; }
test -d "/etc/nginx/bx/site_enabled" && { rm -fr /etc/nginx/bx/site_enabled ; mkdir -p /etc/nginx/bx/site_enabled ; }


