# if set to 1, tells rpmbuild to exit 
# if it finds files that are in the $RPM_BUILD_ROOT directory but not listed as part of the package
%define _unpackaged_files_terminate_build 1
# for docs the same meaning
%define _missing_doc_files_terminate_build 0
# not terminated if requires contains arch depended packages
%define _binaries_in_noarch_packages_terminate_build   0
# usage mariadb and systemd for Centos7
%define use_mariadb (0%{?rhel} && 0%{?rhel} >= 7)
%define use_systemd (0%{?rhel} && 0%{?rhel} >= 7)

# local macros
%define bitrix_home   /home/bitrix
%define bitrix_user   bitrix
%define bitrix_group  bitrix
%define bitrix_pass   bitrix

%define bitrix_source   bitrix-env
%define bitrix_type     general
%define bitrix_conflicts bitrix-env-crm

%define bitrix_rel    11

Name:       bitrix-env
Version:    7.3
Release:    %{bitrix_rel}%{?dist}
Summary:    Bitrix application web environment

Group:      Applications/Web
License:    Copyright Bitrix 2017
URL:        http://www.bitrixsoft.com/
Packager:   Bitrix Inc., <support@bitrixsoft.com>

Source0:    %{bitrix_source}.tar.gz
# access to this varible throw RPM_BUILD_ROOT
BuildRoot:  %(mktemp -ud %{_tmppath}/%{bitrix_source}-%{version}-%{release}-XXXXXX)
BuildArch:  noarch

# beta usage, conflicts with old package
Conflicts: bitrix-env4
Conflicts: %{bitrix_conflicts}

# Common Requires
Requires: bash, sudo, ntp, tar, gzip, stunnel, catdoc, bc
Requires: httpd >= 2.2, mod_geoip, mod_ssl
Requires: rsync, librsync-devel, xinetd, msmtp >= 1.4.13
Requires: libtasn1, libtasn1-devel, libtasn1-tools, poppler >= 0.12.0, poppler-utils >= 0.12.0
Requires: sqlite2, sqlite2-devel, expect, GeoIP, openssh, openssh-clients, libidn, libidn-devel
Requires: krb5-workstation, pam_krb5, graphviz

# Version controll
Requires: mercurial,etckeeper

# Configuration mgmt
Requires: bx-ansible,ethtool
requires: python-passlib,MySQL-python,libselinux-python,python-setuptools,python-keyczar

# parse files and manage ssh keys
Requires: perl-JSON,perl-Moose,perl-Proc-Daemon,perl-Net-DNS,perl-YAML-Tiny,perl-YAML-LibYAML,perl-DBD-MySQL

%if 0%{?rhel}==6
# Mysql
Requires: mysql >= 5.1, mysql-server >= 5.1

# Php
Requires: php, php-common, php-cli, php-gd, php-mbstring, php-mcrypt, php-mysqlnd
Requires: php-ldap, php-pspell, php-pecl-xdebug
Requires: php-zipstream, php-pecl-geoip
Requires: php-pear, php-pecl-memcache, php-pecl-rrd

Requires: httpd-tools
Requires: cronie, cronie-anacron, crontabs, yum-plugin-merge-conf
Requires: perl-IO-Interface,mod_rpaf,bx-nginx,authbind

%endif

%if 0%{?rhel}==7
# Mysql => mariadb
Requires: mysql, mysql-server

# Php
Requires: php, php-common, php-cli, php-gd, php-mbstring, php-mcrypt, php-mysqlnd
Requires: php-ldap, php-pspell, php-pecl-xdebug
Requires: php-zipstream, php-pecl-geoip
Requires: php-pear, php-pecl-memcache, php-pecl-rrd

Requires: httpd-tools
Requires: cronie, cronie-anacron, crontabs, yum-plugin-merge-conf
Requires: bx-nginx

%endif


%description
Bitrix application web environment.

# unpack sources files
%prep
%setup -q -n %{bitrix_source}

%install
rm -rf %{buildroot}

# nginx
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/nginx/bx/{conf,site_ext_enabled,site_enabled,site_avaliable,maps,settings}
# apache
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/httpd/bx/{conf,custom}
# cluster nodes
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/bx_cluster/nodes
# sphinx
mkdir -p $RPM_BUILD_ROOT%{_sysconfdir}/sphinx/bx/{search_index,dicts}
# webdir 
mkdir -p $RPM_BUILD_ROOT/opt/webdir/{webkey,bin,etc,logs,temp,providers}

cp -fr etc $RPM_BUILD_ROOT/
cp -fr var $RPM_BUILD_ROOT/
cp -fr root $RPM_BUILD_ROOT/
cp -fr opt $RPM_BUILD_ROOT/

%post
# test install or upgrade
if [ $1 -eq 1 ]; then
  RPM_ACTION=install
elif [ $1 -gt 1 ]; then
  RPM_ACTION=upgrade
else
  RPM_ACTION=undefined
fi

BITRIX_ENV_VER=%{version}.%{bitrix_rel}
BITRIX_ENV_TYPE=%{bitrix_type}

/opt/webdir/bin/rpm_package/post.sh "$RPM_ACTION" "$BITRIX_ENV_VER" "$BITRIX_ENV_TYPE"
/opt/webdir/bin/rpm_package/crm.sh "$RPM_ACTION" "$BITRIX_ENV_VER" "$BITRIX_ENV_TYPE"

# Remove BitrixEnv
%postun
if [ $1 -eq 0 ]; then

	service stunnel stop >/dev/null 2>&1 ;
	chkconfig --del stunnel >/dev/null 2>&1 ;
	rm -rf /etc/init.d/stunnel >/dev/null 2>&1 ;
	rm -rf /etc/stunnel/stunnel.conf >/dev/null 2>&1 ;

	sed  -i".$UPDATE_TM" '/bitrix\/modules\/main\/tools\/cron\_events/d' /etc/crontab ;
	sed  -i".$UPDATE_TM" '/xmppd\.sh/d' /etc/crontab ;
	sed  -i".$UPDATE_TM" '/smtpd\.sh/d' /etc/crontab ;
	sed  -i".$UPDATE_TM" '/root\/bitrix\-env\/check\_bitrixenv\_chown/d' /etc/crontab ;

	chkconfig --del bvat >/dev/null 2>&1 ;
	rm -rf /etc/init.d/bvat >/dev/null 2>&1 ;

	sed -i".$UPDATE_TM" '/;bitrix-env/d' /etc/php.ini >/dev/null 2>&1 ;
	sed -i".$UPDATE_TM" '/#bitrix-env/d' /etc/profile >/dev/null 2>&1 ;
	sed -i".$UPDATE_TM" '/#bitrix-env/d' /root/.bash_profile >/dev/null 2>&1 ;
	sed -i".$UPDATE_TM" '/#bitrix-env/d' /etc/nginx/mime.types >/dev/null 2>&1 ;
fi


%posttrans

%clean
rm -rf %{buildroot}

%files
%attr(0644,root,root)

/etc/httpd/conf/httpd.conf.bx
/etc/httpd/bx/conf/default.conf.bx
/etc/httpd/bx/conf/mod_geoip.conf.bx
/etc/httpd/bx/conf/mod_rpaf.conf.bx
/etc/httpd/bx/conf/php.conf.bx
/etc/httpd/bx/custom/z_bx_custom.conf.bx
/etc/httpd/bx/conf/default.conf.bx_centos7
/etc/httpd/bx/conf/mod_geoip.conf.bx_centos7
/etc/httpd/bx/conf/mod_rpaf.conf.bx_centos7
/etc/httpd/bx/conf/php.conf.bx_centos7
/etc/httpd/bx-scale/httpd-scale
/etc/httpd/bx-scale/httpd-scale.service
/etc/httpd/bx-scale/httpd-scale.conf
/etc/httpd/conf/httpd.conf.bx_centos7
/etc/init.d/bvat.bx
/etc/init.d/stunnel.bx
/etc/logrotate.d/msmtp.bx
/etc/my.cnf.bx
/etc/my.cnf.bx_mysql56
/etc/my.cnf.bx_mysql57
/etc/mysql/conf.d/z_bx_custom.cnf.bx
/etc/nginx/*
/etc/stunnel/stunnel.conf.bx
/etc/sudoers.d/bitrix
/root/*
/var/www/bitrixenv_error/*
/opt/*
/etc/ansible/*

%defattr(0664,root,root)
%config(noreplace) /etc/nginx/bx/server_monitor.conf
%config(noreplace) /etc/php.d/bitrixenv.ini

%changelog
* Tue May 19 2015 Ekaterina Shemaeva <support@bitrix.ru>
- bag=59490; check the connection to the AD server for localized names
- bag=59419; creating NOT_DEFINED entries in the configuration files 
- bag=59420; added ability to change the domain for the server
- bag=61229; added ability to change netbios hostname from menu
- bag; fixes options for sites which used cp1251 charset

* Wed Apr 16 2014 Ekaterina Shemaeva <support@bitrix.ru>
- MySQL role
- Memcached Role
- Manage host in Pool
- Manage sites in Pool
