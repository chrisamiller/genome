#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Test::Deep qw(cmp_bag);
use Genome::Test::Factory::InstrumentData::Solexa;
use Genome::Test::Factory::Model::ImportedReferenceSequence;
use Genome::Test::Factory::Build;
use Genome::Test::Factory::SoftwareResult::User;
use Genome::Test::Data qw(get_test_file);
use Sub::Override;
use Cwd qw(abs_path);

my $pkg = 'Genome::InstrumentData::Command::AlignAndMerge';
use_ok($pkg);

my $test_data_dir = __FILE__.'.d';

my $ref_seq_model = Genome::Test::Factory::Model::ImportedReferenceSequence->setup_object;
my $ref_seq_build = Genome::Test::Factory::Build->setup_object(
    model_id => $ref_seq_model->id,
    id => 'a77284b86c934615baaf2d1344399498',
);

use Genome::Model::Build::ReferenceSequence;
my $override = Sub::Override->new(
    'Genome::Model::Build::ReferenceSequence::full_consensus_path',
    sub { return abs_path(get_test_file('NA12878', 'human_g1k_v37_20_42220611-42542245.fasta')); }
);
use Genome::InstrumentData::AlignmentResult;
my $override2 = Sub::Override->new(
    'Genome::InstrumentData::AlignmentResult::_prepare_reference_sequences',
    sub { return 1; }
);

my $aligner_index = Genome::Model::Build::ReferenceSequence::AlignerIndex->__define__(
    reference_build => $ref_seq_build,
    aligner_version => 'test',
    aligner_name => 'speedseq',
    aligner_params => undef,
    output_dir => get_test_file('NA12878', File::Spec->join(qw(aligner_index speedseq))),
);
ok($aligner_index, 'Created speedseq aligner index');
$aligner_index->recalculate_lookup_hash;

my $instrument_data_1 = Genome::Test::Factory::InstrumentData::Solexa->setup_object(
    flow_cell_id => '12345ABXX',
    lane => '1',
    subset_name => '1',
    run_name => 'example',
    id => '2893815019',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 10,
    rev_clusters => 10,
);
$instrument_data_1->bam_path(File::Spec->join($test_data_dir, '-533e0bb1a99f4fbe9e31cf6e19907133.bam'));
my $instrument_data_2 = Genome::Test::Factory::InstrumentData::Solexa->setup_object(
    library_id => $instrument_data_1->library_id,
    flow_cell_id => '12345ABXX',
    lane => '2',
    subset_name => '2',
    run_name => 'example',
    id => 'NA12878',
    run_type => 'Paired',
    fwd_read_length => 100,
    rev_read_length => 100,
    fwd_clusters => 10,
    rev_clusters => 10,
);
$instrument_data_2->bam_path(get_test_file('NA12878', 'NA12878.20slice.30X.bam'));
my @two_instrument_data = ($instrument_data_1, $instrument_data_2);

my $result_users = Genome::Test::Factory::SoftwareResult::User->setup_user_hash(
    reference_sequence_build => $ref_seq_build,
);

my $command = Genome::InstrumentData::Command::AlignAndMerge->create(
    instrument_data => [@two_instrument_data],
    reference_sequence_build => $ref_seq_build,
    name => 'speedseq',
    version => 'test',
    params => 'threads => 8, sort_memory => 8',
    result_users => $result_users,
    picard_version => '1.46',
    samtools_version => 'r963',
);
ok($command->execute, 'Command executed correctly');
ok($command->result, 'Merged result created');

my $merged_cmp = Genome::Model::Tools::Sam::Compare->execute(
    file1 => $command->result->bam_file,
    file2 => File::Spec->join($test_data_dir, 'merged_alignment_result.bam'),
);
ok($merged_cmp->result, 'Merged bam as expected');

my @per_lane_results = map { Genome::InstrumentData::AlignmentResult::Speedseq->get(instrument_data => $_) } $command->instrument_data;
ok(@per_lane_results, 'Per-lane result created correctly');
cmp_bag([$command->per_lane_alignment_result_ids], [map { $_->id } @per_lane_results], 'Per lane result ids match');
cmp_bag([$command->per_lane_alignment_results], [@per_lane_results], 'Per lane results match');

for my $per_lane_result (@per_lane_results) {
    my $per_lane_cmp = Genome::Model::Tools::Sam::Compare->execute(
        file1 => $per_lane_result->get_bam_file,
        file2 => File::Spec->join($test_data_dir, 'alignment_result.' . $per_lane_result->instrument_data->id . '.bam'),
    );
    ok($per_lane_cmp->result, 'Per-lane bam as expected');
}

done_testing;
