#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Utility::Test qw(compare_ok);
use Genome::File::Vcf::Differ;

my $pkg = 'Genome::Model::Tools::Vcf::AnnotateWithFpkm';
use_ok($pkg);

my $TEST_DATA_VERSION = 'v2'; #Bump this when test data changes
my $data_dir = Genome::Utility::Test->data_dir_ok($pkg, $TEST_DATA_VERSION);

subtest "output vcf" => sub {
    my $out = Genome::Sys->create_temp_file_path;
    run($out);

    my $expected_out = File::Spec->join($data_dir, "expected_snvs.vcf.gz");
    my $differ = Genome::File::Vcf::Differ->new($out, $expected_out);
    my $diff = [$differ->diff];
    is_deeply($diff, [], "Found no differences between $out and (expected) $expected_out") or
        diag Data::Dumper::Dumper($diff);

};

done_testing;

sub run {
    my $out = shift;

    my $cmd = $pkg->create(
        vcf_file => File::Spec->join($data_dir, "snvs_with_vep.vcf.gz"),
        fpkm_file => File::Spec->join($data_dir, "test.fpkm"),
        sample_name => 'TEST-patient1-somval_tumor1',
        output_file => $out,
    );
    ok($cmd->isa($pkg), "Command created ok");
    ok($cmd->execute, "Command executed ok");
    like($cmd->status_message, qr/Could not find a gene for intergenic transcript/, "Status message for one intergenic transcript as expected");
}
