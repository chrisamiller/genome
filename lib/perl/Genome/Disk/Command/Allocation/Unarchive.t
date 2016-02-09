#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More tests => 8;
use File::Temp 'tempdir';
use Filesys::Df qw();
require Sub::Install;
use Test::Exception;

use Genome::Test::Factory::Model::SingleSampleGenotype;
use Genome::Test::Factory::Build;

use_ok('Genome::Disk::Command::Allocation::Unarchive') or die;
use_ok('Genome::Disk::Allocation') or die;
use_ok('Genome::Disk::Volume') or die;

$Genome::Disk::Allocation::CREATE_DUMMY_VOLUMES_FOR_TESTING = 0;

my ($analysis_project, $test_dir, $group, $volume, $archive_volume);
subtest 'setup' => sub{
    plan tests => 5;

    $analysis_project = Genome::Config::AnalysisProject->__define__(name => 'test AnP for Unarchive.t');

    # Temp testing directory, used as mount path for test volumes and allocations
    $test_dir = tempdir(
        'allocation_testing_XXXXXX',
        TMPDIR => 1,
        UNLINK => 1,
        CLEANUP => 1,
    );

    # Create test group
    $group = Genome::Disk::Group->create(
        disk_group_name => 'test',
        subdirectory => 'info',
        permissions => '775',
        setgid => 1,
        unix_uid => '1',
        unix_gid => '1',
    );
    ok($group, 'created test disk group');

    # Create temp archive volume
    my $archive_volume_path = tempdir(
        "test_volume_XXXXXXX",
        DIR => $test_dir,
        CLEANUP => 1,
        UNLINK => 1,
    );
    $archive_volume = Genome::Disk::Volume->create(
        hostname => 'test',
        physical_path => 'test',
        mount_path => $archive_volume_path,
        disk_status => 'active',
        can_allocate => 1,
        total_kb => Filesys::Df::df($archive_volume_path)->{blocks},
    );
    ok($archive_volume, 'created test volume');

    # Create temp active volume
    my $volume_path = tempdir(
        "test_volume_XXXXXXX",
        DIR => $test_dir,
        CLEANUP => 1,
        UNLINK => 1,
    );
    $volume = Genome::Disk::Volume->create(
        hostname => 'test',
        physical_path => 'test',
        mount_path => $volume_path,
        disk_status => 'active',
        can_allocate => 1,
        total_kb => Filesys::Df::df($volume_path)->{blocks},
    );
    ok($volume, 'created test volume');

    my $assignment = Genome::Disk::Assignment->create(
        group => $group,
        volume => $volume,
    );
    ok($assignment, 'added volume to test group successfully');
    Genome::Sys->create_directory(join('/', $volume->mount_path, $group->subdirectory));

    my $archive_assignment = Genome::Disk::Assignment->create(
        group => $group,
        volume => $archive_volume,
    );
    ok($archive_assignment, 'added archive volume to test group successfully');
    Genome::Sys->create_directory(join('/', $archive_volume->mount_path, $group->subdirectory));

    # Override these methods so archive/active volume linking works for our test volumes
    Sub::Install::reinstall_sub({
            code => sub { return $archive_volume->mount_path },
            into => 'Genome::Disk::Volume',
            as => 'archive_volume_prefix',
        });

    Sub::Install::reinstall_sub({
            code => sub { return $volume->mount_path },
            into => 'Genome::Disk::Volume',
            as => 'active_volume_prefix',
        });

};

subtest 'unarchive allocation filas without correct owner' => sub{
    plan tests => 5;

    my $allocation = _create_an_archived_allocation(UR::Value->get('test'));
    my $cmd = Genome::Disk::Command::Allocation::Unarchive->create(
        allocations => [$allocation],
        analysis_project => $analysis_project,
    );
    ok($cmd, 'created unarchive command');
    throws_ok(sub { $cmd->execute }, qr/currently not handled/, 'command fails with unsupported owner');

};

subtest 'unarchive allocation programatically' => sub{
    plan tests => 7;

    my $sr = Genome::InstrumentData::AlignmentResult::Speedseq->__define__(test_name => 'testing Unarchive.t');
    my $allocation = _create_an_archived_allocation($sr);
    my $cmd = Genome::Disk::Command::Allocation::Unarchive->create(
        allocations => [$allocation],
        analysis_project => $analysis_project,
    );

    ok($cmd->execute, 'successfully executed unarchive command');
    is($allocation->volume->id, $volume->id, 'allocation moved to active volume');
    ok($allocation->is_archived == 0, 'allocation is not archived');
    my @users = $sr->users;
    is($users[0]->user, $analysis_project, 'analysis project linked to SR whose allocation was unarchived');

};

subtest 'unarchive allocation from the CLI' => sub{
    plan tests => 5;

    my $model = Genome::Test::Factory::Model::SingleSampleGenotype->setup_object(name => 'test model for Unarchive.t');
    Genome::Config::AnalysisProject::ModelBridge->create(analysis_project => $analysis_project, model => $model);
    my $build = Genome::Test::Factory::Build->setup_object(model_id => $model->id);
    my $allocation = _create_an_archived_allocation($build);
    my @args = ($allocation->id, '--analysis-project', $analysis_project->id);
    my $rv = Genome::Disk::Command::Allocation::Unarchive->_execute_with_shell_params_and_return_exit_code(@args);
    ok($rv == 0, 'successfully executed command using simulated command line arguments');
    is($allocation->volume->id, $volume->id, 'allocation updated as expected after archive');

};

subtest 'unarchive allocation owned by imported instrument data' => sub{
    plan tests => 7;

    my $imported = Genome::InstrumentData::Imported->create();
    ok($imported, 'create imported instrument data');
    my $allocation = _create_an_archived_allocation($imported);
    ok(
        Genome::Disk::Command::Allocation::Unarchive->execute(
            allocations => [$allocation],
            analysis_project => $analysis_project,
        ),
        'unarchive imported instrument data',
    );
    my $bridge = $analysis_project->analysis_project_bridges(instrument_data => $imported);
    ok($bridge, 'added imported instrument data to analysis project');
    is($bridge->status, 'skipped', 'bridge status is skipped');

};

done_testing();

sub _create_an_archived_allocation {
    my ($owner) = @_;
    die 'No owner given to create allocation!' if not $owner;

    # Make test allocation
    my $allocation_path = tempdir(
        "allocation_test_1_XXXXXX",
        CLEANUP => 1,
        UNLINK => 1,
        DIR => $test_dir,
    );
    my $allocation = Genome::Disk::Allocation->create(
        disk_group_name => $group->disk_group_name,
        allocation_path => $allocation_path,
        kilobytes_requested => 100,
        owner_class_name => $owner->class,
        owner_id => $owner->id,
        mount_path => $archive_volume->mount_path,
    );
    ok($allocation, 'created test allocation');
    $allocation->status('archived');
    ok($allocation->is_archived, 'allocation is archived prior to running command, as expected');

    # Create a test tarball
    system("touch " . $allocation->absolute_path . "/a.out");
    Genome::Sys->tar(
        tar_path => $allocation->absolute_path . "/archive.tar",
        input_directory => $allocation->absolute_path,
    );
    ok(-e join('/', $allocation->absolute_path, 'archive.tar'), 'archive tarball successfully created');
    unlink join('/', $allocation->absolute_path, 'a.out');

    return $allocation;
}

