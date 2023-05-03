#!/usr/bin/perl
#
# SPDX-FileCopyrightText: 2023 Zextras <https://www.zextras.com>
#
# SPDX-License-Identifier: GPL-2.0-only
#

=begin
About this script:
    → start LDAP
    → bind ldap
    → get the value of zimbraLDAPSchemaVersion from LDAP
    → iterate through what we call ldap_attribute_cleanup_dir containing cleanup JSON files
    → sort cleanup files in ascending order
    → compare timestamp from cleanup filename with zimbraLDAPSchemaVersion. if it’s greater, that
    means we need to apply cleanups from this update file
    → remove attributes declared in cleanup by searching all entries containing said attribute 
    → unbind ldap
    → exit
=cut

use strict;
use lib "/opt/zextras/common/lib/perl5";
use Zimbra::Util::Common;
use File::Path;
use Net::LDAP;
use Net::LDAP::LDIF;
use Net::LDAP::Entry;
use JSON::PP;
use File::Basename;
use experimental 'smartmatch';

my $source_config_dir = "/opt/zextras/common/etc/openldap";
my $ldap_attribute_cleanup_dir = "$source_config_dir/zimbra/cleanup/attrs";
my $ldap_root_password = getLocalConfig("ldap_root_password");
my $ldap_master_url = getLocalConfig("ldap_master_url");
my $ldap_is_master = getLocalConfig("ldap_is_master");
my $ldap_starttls_supported = getLocalConfig("ldap_starttls_supported");
my $zimbra_tmp_directory = getLocalConfig("zimbra_tmp_directory");

if (lc($ldap_is_master) ne "true") {
    exit(0);
}

if (!-d $zimbra_tmp_directory) {
    File::Path::mkpath("$zimbra_tmp_directory");
}

my $rc = qx(/opt/zextras/bin/ldap start);

my @masters = split(/ /, $ldap_master_url);
my $master_ref = \@masters;
my $ldap = Net::LDAP->new($master_ref) or die "$@";

# startTLS Operation if available
my $mesg;
if ($ldap_master_url !~ /^ldaps/i) {
    if ($ldap_starttls_supported) {
        $mesg = $ldap->start_tls(
            verify => 'none',
            capath => "/opt/zextras/conf/ca",
        ) or die "start_tls: $@";
        $mesg->code && die "TLS: " . $mesg->error . "\n";
    }
}

# bind ldap or exit with error on failure fail
$mesg = $ldap->bind("cn=config", password => "$ldap_root_password");
if ($mesg->code()) {
    print "Unable to bind: $!";
    exit(0);
}

# get zimbraLDAPSchemaVersion from LDAP server
my $zimbra_ldap_schema_version;
my $last_applied_update_version;
my $result = $ldap->search(base => 'cn=zimbra', filter => '(zimbraLDAPSchemaVersion=*)', attrs => [ 'zimbraLDAPSchemaVersion' ]);
if ( $result->count > 0 ) {
    my $entry = $result->entry(0);
    $zimbra_ldap_schema_version = $entry->get_value('zimbraLDAPSchemaVersion');
    $last_applied_update_version = $zimbra_ldap_schema_version;
    &print_separater("-", "40");
    print "Installed LDAP Schema Version: $zimbra_ldap_schema_version \n";
}
else {
    print "Unable to get zimbraLDAPSchemaVersion from LDAP.\n";
    $ldap->unbind;
    exit(0);
}

# read updates folder and prepare each file for update;
if (-d "$ldap_attribute_cleanup_dir") {
    opendir(DIR, "$ldap_attribute_cleanup_dir") or die "Cannot opendir $ldap_attribute_cleanup_dir: $!\n";
    my @cleanup_files =  sort { $a <=> $b } readdir(DIR);
    while ( my $file = shift @cleanup_files ) {
        next unless (-f "$ldap_attribute_cleanup_dir/$file");
        next unless ($file =~ m/json/);
        my $infile = "$ldap_attribute_cleanup_dir/$file";
        &prepare_cleanup_file($infile);
    }
    closedir DIR;
    &print_separater("-", "80");
}
else {
    print "LDAP Schema/Attributes update directory($ldap_attribute_cleanup_dir) not found.\nUnable to process LDAP updates.\n";
    $ldap->unbind;
    exit(0);
}

=begin print_separater
    print_separater($char<string>, $length<int>);
Prints $char $length times prepended by a new line;
=cut
sub print_separater(){
    my ($char, $length) = @_;
    print $char x $length;
    print "\n";
}

=begin getLocalConfig
    getLocalConfig($key<string>);
Returns value of key from localconfig, using zmlocalconfig util.
=cut
sub getLocalConfig {
    my $key = shift;

    return $main::loaded{lc}{$key}
        if (exists $main::loaded{lc}{$key});

    my $val = qx(/opt/zextras/bin/zmlocalconfig -x -s -m nokey ${key} 2> /dev/null);
    chomp $val;
    $main::loaded{lc}{$key} = $val;
    return $val;
}

=begin prepare_cleanup_file
    prepare_cleanup_file($filename<string>);
Prepare each update files for updating.
=cut
sub prepare_cleanup_file(){
    my ($infile) = @_;
    my $infile_base_name = basename($infile);
    (my $timestamp_from_file = $infile_base_name) =~ s/\.[^.]+$//;
    chomp $timestamp_from_file;
    &print_separater("-", "80");
    if ($timestamp_from_file > $zimbra_ldap_schema_version) {
        open(FH, '<', $infile) or die "Cannot open file $infile for reading: $!\n";
        my $raw_json = join '', <FH>;
        my $json = new JSON::PP;
        eval {
            my $json_decoded = $json->decode($raw_json);
            print "Executing cleanup from ", $timestamp_from_file, ".json\n";
                my @attributes = @{$json_decoded->{"delete"}};
                &apply_cleanup($timestamp_from_file, \@attributes);
            1;
        } or do {
            my $e = $@;
            # TODO: should fail and not skip
            print "Skipping: $timestamp_from_file.json\n    Reason: $e\n";
        };
    }
    else {
        print "Skipping: $timestamp_from_file.json\n    Reason: not eligible for this update.\n";
    }
    close(FH);
    # end, process only eligible update files;
}


=begin apply_cleanup
    apply_cleanup($timestamp_from_file<string>, @attributes<array>);
Removes the attributes in the entry.
=cut
sub apply_cleanup {
    my ($timestamp_from_file, $attributes) = @_;
    foreach my $attribute (@$attributes) {
        $mesg = $ldap ->search(
            base=>"",
            filter=>"&(objectClass=*)($attribute=*)",
            scope=>"sub",
        );
        my @entries = $mesg->entries;
        my $size = @entries;
        print STDOUT "Found $size entries with attribute $attribute.\n";

        foreach my $entry (@entries)  {
            $entry->delete($attribute);
            $entry->update ( $ldap ); # applies delete
        }
    }
    print STDOUT "...Done.\n";
}
$ldap->unbind;
exit(0);
