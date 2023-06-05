#!/usr/bin/perl

# SPDX-FileCopyrightText: 2022 Synacor, Inc.
# SPDX-FileCopyrightText: 2022 Zextras <https://www.zextras.com>
#
# SPDX-License-Identifier: GPL-2.0-only

use strict;
use lib '/opt/zextras/common/lib/perl5';
use Net::LDAP;
use XML::Simple;

if ( ! -d "/opt/zextras/common/etc/openldap/schema" ) {
    print STDERR "ERROR: openldap does not appear to be installed - exiting\n";
    exit(1);
}

my $id = getpwuid($<);
chomp $id;
if ($id ne "zextras") {
    print STDERR "Error: must be run as zextras user\n";
    exit (1);
}


my $localxml = XMLin("/opt/zextras/conf/localconfig.xml");
my $ldap_root_password = $localxml->{key}->{ldap_root_password}->{value};
chomp($ldap_root_password);

my $ldap = Net::LDAP->new('ldapi://%2fopt%2fzextras%2fdata%2fldap%2fstate%2frun%2fldapi/') or die "$@";

my $mesg = $ldap->bind("cn=config", password=>"$ldap_root_password");

$mesg->code && die "Bind: ". $mesg->error . "\n";

my $basedn="cn=config";
print STDOUT "Searching config entries using zimbraShareInfo...\n";
$mesg = $ldap ->search(
    base=>"$basedn",
    filter=>"(olcDbIndex=zimbraShareInfo sub)",
    scope=>"one",
);

my ($dn,$entry,$cn,$err);

my @entries = $mesg->entries;
my $size = @entries;

print STDOUT "Found $size entries.\n";

foreach $entry (@entries)  {
    $dn=$entry->dn();
    $mesg = $ldap->modify(
        $dn,
        delete =>{
            olcDbIndex => [
                "zimbraShareInfo sub"
            ]
        }
    );
    $mesg->code && print STDERR "Failed to remove zimbraShareInfo on entry with dn: $dn \n", $mesg->error ;
}
print STDOUT "Done.\n";

$ldap->unbind;
