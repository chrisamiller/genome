#!/usr/bin/env genome-perl

use strict;
use warnings;

use above 'Genome';
use Set::Scalar;
use Test::MockObject;
use Test::More tests => 2;

my $class = 'Genome::Site::TGI::Command::SyncSysUserWithLdap';
use_ok($class);

my @apipe_uids = (qw/ apipe apipe-builder apipe-tester /);
my $apipe_users = Set::Scalar->new( map{$_.'@'.Genome::Config::get('email_domain')} @apipe_uids );
my @apipe_db_users = map { my $o = Test::MockObject->new; $o->set_always('email', $_); $o; } $apipe_users->members;

subtest 'lpad_users' => sub {
    plan tests => 1;

    my $ldap_users = $class->get_ldap_users;
    my $users = Set::Scalar->new(keys %$ldap_users);
    ok($users->is_proper_superset($apipe_users), 'Found apipe users in ldap users');

};

subtest 'changes delete' => sub {
    plan tests => 2;

    my %ldap_users = map { $_ => 1 } $apipe_users->members;
    my $changes = Genome::Site::TGI::Command::SyncSysUserWithLdap::get_changes(\%ldap_users, \@apipe_db_users);
    is_deeply($changes, {}, 'no changes needed');

    delete $ldap_users{ $apipe_db_users[0]->email };
    $changes = Genome::Site::TGI::Command::SyncSysUserWithLdap::get_changes(\%ldap_users, \@apipe_db_users);
    is_deeply($changes, { delete => [ @apipe_db_users[0] ] }, 'need to delete '.$apipe_db_users[0]->email);

};

done_testing();
