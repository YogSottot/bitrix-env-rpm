#### Исходные коды bitrix-env

Один коммит — одно обновление.  
Репозиторий создан для удобства отслеживания изменений в новых версиях пакета.  

* **Способ получения оригинального пакета с исходным кодом.**  

Добавляем файл для репозитория /etc/yum.repos.d/bitrix-source.repo с содержимым:  
```bash
[bitrix-source-9]
name=Bitrix Packages Source for Enterprise Linux 9 - x86_64
baseurl=https://repo.bitrix.info/dnf/SRPMS
enabled=1
gpgcheck=1
priority=1
failovermethod=priority
gpgkey=https://repo.bitrix.info/dnf/RPM-GPG-KEY-BitrixEnv-9
```
```bash
dnf download --source bitrix-env
# или
yum install yum-utils && yumdownloader --source bitrix-env
rpm -Uvh  bitrix-env-9.0-0.el9.src.rpm
# распаковано в /root/rpmbuild
```

* **Сборка из исходных кодов**  

```bash
dnf install mock dnf-utils -y
# или
yum install yum-utils mock -y
```
Настроить mock по инструкции
https://github.com/rpm-software-management/mock/wiki#setup

```bash
git clone https://github.com/YogSottot/bitrix-env-rpm ~/rpmbuild
cd ~/rpmbuild/SOURCES/
tar czf bitrix-env.tar.gz bitrix-env
rm -rf bitrix-env
spectool -g -R ~/rpmbuild/SPECS/bitrix-env.noarch.spec
rpmbuild -bs ~/rpmbuild/SPECS/bitrix-env.noarch.spec
mock -r epel-9-x86_64 --rebuild ~/rpmbuild/SRPMS/bitrix-env-9.0-0.el9.src.rpm
# реультат в
/var/lib/mock/epel-7-x86_64/result/bitrix-env-9.0-0.el9.noarch.rpm
```


Получили пакет для centos 9.  
