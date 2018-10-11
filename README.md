#### Модификация bitrix-env + php-fpm



* **Способ получения оригинального пакета с исходным кодом.**  

Добавляем файл для репозитория /etc/yum.repos.d/bitrix-source.repo с содержимым:  
```bash
[bitrix-source]
name=$OS $releasever - source
failovermethod=priority
baseurl=http://repos.1c-bitrix.ru/yum/SRPMS
enabled=1
gpgcheck=1
gpgkey=http://repos.1c-bitrix.ru/yum/RPM-GPG-KEY-BitrixEnv
```
```bash
dnf download --source bitrix-env
# или
yum install yum-utils && yumdownloader --source bitrix-env
rpm -Uvh  bitrix-env-7.3-11.src.rpm
# распаковано в /root/rpmbuild
```

Собираем модифицированный bitrix-env

```bash
dnf install mock dnf-utils -y
# или
yum install yum-utils mock -y
```
Настройте mock по инструкции
https://github.com/rpm-software-management/mock/wiki#setup

```bash
git clone https://github.com/YogSottot/bitrix-env-rpm ~/rpmbuild
cd ~/rpmbuild/SOURCES/
tar czf bitrix-env.tar.gz bitrix-env
rm -rf bitrix-env
spectool -g -R ~/rpmbuild/SPECS/bitrix-env.noarch.spec
rpmbuild -bs ~/rpmbuild/SPECS/bitrix-env.noarch.spec
mock -r epel-7-x86_64 --rebuild ~/rpmbuild/SRPMS/bitrix-env-7.3-0.fc28.src.rpm
# реультат в
/var/lib/mock/epel-7-x86_64/result/bitrix-env-7.3-0.el7.noarch.rpm
```


Получили пакет для centos 7. Если нужен centos 6 — используем ```mock -r epel-6-x86_64 --rebuild ~/rpmbuild/SRPMS/bitrix-env-7.3-0.fc28.src.rpm```  
