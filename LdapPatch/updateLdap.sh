# SPDX-FileCopyrightText: 2022 Zextras <https://www.zextras.com>
#
# SPDX-License-Identifier: GPL-2.0-only

# !/bin/bash 

if [ $USER != "root" ]; then
  echo -e "\n[Error] - User must be root to execute this script..\n"
  exit 0
fi

# set required permissions
chown -R zextras:zextras ../LdapPatch
chmod -R o+w /opt/zextras/common/etc/openldap/schema  
chmod o+w /opt/zextras/conf/carbonio.ldif
chmod +w /opt/zextras/conf/attrs/attrs.xml
chmod -R o+w /opt/zextras/common/etc/openldap/zimbra

patchDir=`pwd`
su - zextras -c "cd $patchDir && ant update-ldap-schema -Dzimbra.buildinfo.version=8.8.15"
su - zextras -c "cd $patchDir && perl processLdap.pl"

