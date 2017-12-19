#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above "Genome";

require File::Compare;
require Genome::Utility::Test;
use Test::More;

use_ok('Genome::InstrumentData::Command::Import::Basic') or die;
use_ok('Genome::InstrumentData::Command::Import::WorkFlow::Helpers') or die;
Genome::InstrumentData::Command::Import::WorkFlow::Helpers->overload_uuid_generator_for_class('Genome::InstrumentData::Command::Import::WorkFlow::SanitizeAndSplitBam');

my $test_dir = Genome::Utility::Test->data_dir_ok('Genome::InstrumentData::Command::Import', 'v02');
my $source_sra = $test_dir.'/input.sra';
ok(-s $source_sra, 'source sra exists') or die;

my $analysis_project = Genome::Config::AnalysisProject->create(name => '__TEST_AP__');
ok($analysis_project, 'create analysis project');
my $library = Genome::Library->create(
    name => '__TEST_SAMPLE__-extlibs', sample => Genome::Sample->create(name => '__TEST_SAMPLE__')
);
ok($library, 'Create library');

my $environment_file = $test_dir .'/config.yml';
my $add_env_cmd = Genome::Config::AnalysisProject::Command::AddEnvironmentFile->create(
   analysis_project => $analysis_project,
   environment_file => $environment_file,
);
ok($add_env_cmd, 'Add ENV command.');
ok($add_env_cmd->execute, 'Execute Add ENV command');

my $cmd = Genome::InstrumentData::Command::Import::Basic->create(
    analysis_project => $analysis_project,
    library => $library,
    source_files => [$source_sra],
    import_source_name => 'sra',
    instrument_data_properties => [qw/ lane=2 flow_cell_id=XXXXXX /],
);
ok($cmd, "create import command");
ok($cmd->execute, "execute import command") or die;

my $md5 = Genome::InstrumentData::Command::Import::WorkFlow::Helpers->load_md5($source_sra.'.md5');
ok($md5, 'load source md5');
my @instrument_data = map { $_->instrument_data } Genome::InstrumentDataAttribute->get(
    attribute_label => 'original_data_path_md5',
    attribute_value => $md5,
);
is(@instrument_data, 1, "got instrument data for md5 $md5") or die;;
my $instrument_data = $instrument_data[0];
is($instrument_data->original_data_path, $source_sra, 'original_data_path correctly set');
is($instrument_data->import_format, 'bam', 'import_format is bam');
is($instrument_data->sequencing_platform, 'solexa', 'sequencing_platform correctly set');
is($instrument_data->is_paired_end, 0, 'is_paired_end correctly set');
is($instrument_data->read_count, 148, 'read_count correctly set');
is($instrument_data->read_length, 232, 'read_length correctly set');
is(eval{$instrument_data->attributes(attribute_label => 'original_data_path_md5')->attribute_value;}, 'dcd04a5bcb2d18f29c21c25b0f2387e3', 'original_data_path_md5 correctly set');
is($instrument_data->analysis_projects, $analysis_project, 'set analysis project');

my $allocation = $instrument_data->disk_allocation;
ok($allocation, 'got allocation');
ok($allocation->kilobytes_requested > 0, 'allocation kb was set');

my $bam_path = $instrument_data->bam_path;
ok(-s $bam_path, 'bam path exists');
is($bam_path, $instrument_data->data_directory.'/all_sequences.bam', 'bam path correctly named');
is(eval{$instrument_data->attributes(attribute_label => 'bam_path')->attribute_value}, $bam_path, 'set attributes bam path');
is(File::Compare::compare($bam_path, $test_dir.'/basic-sra-t.bam'), 0, 'bam matches');
is(File::Compare::compare($bam_path.'.flagstat', $test_dir.'/basic-sra-t.bam.flagstat'), 0, 'flagstat matches');

#print $instrument_data->data_directory."\n"; <STDIN>;
done_testing();
