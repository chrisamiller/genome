#!/usr/bin/env genome-perl5.10

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{NO_LSF} = 1;
};

use above "Genome";
use Test::More;
use Test::Exception;
use Genome::Model::ClinSeq;
use Genome::Model::Build::Command::DiffBlessed;

my $patient = Genome::Individual->get(common_name => "PNC6");
ok($patient, "got the PNC6 patient");


my $tumor_rna_sample = $patient->samples(name => "H_LF-09-213F-1221858");
ok($tumor_rna_sample, "found the tumor RNA sample");

my $tumor_genome_sample = $patient->samples(name => "H_LF-09-213F-1221853");
ok($tumor_genome_sample, "found the tumor genome sample");

my $normal_genome_sample = $patient->samples(name => "H_LF-09-213F-1221853");
ok($normal_genome_sample, "found the normal genome sample");

my $tumor_rnaseq_model = Genome::Model::RnaSeq->get(
    id => 2888811351,
);
ok($tumor_rnaseq_model, "got the RNASeq model");

my $wgs_model = Genome::Model::SomaticVariation->get(
    id => 2888915570, 
);
ok($wgs_model, "got the WGS Somatic Variation model");

my $exome_model = Genome::Model::SomaticVariation->get(
    id => 2888844901,
);
ok($exome_model, "got the exome Somatic Variation model");

my $p = Genome::ProcessingProfile::ClinSeq->create(
    id   => -10002,
    name => 'TESTSUITE ClinSeq Profile 2',
);
ok($p, "created a processing profile") or diag(Genome::ProcessingProfile::ClinSeq->error_message);

my $m = $p->add_model(
    name            => 'TESTSUITE-clinseq-model2',
    subclass_name   => 'Genome::Model::ClinSeq',
    subject         => $patient,
);
ok($m, "created a model") or diag(Genome::Model->error_message);

my $i1 = $m->add_input(
    name => 'wgs_model',
    value => $wgs_model, 
);
ok($i1, "add a wgs model to it");

my $i2 = $m->add_input(
    name => 'exome_model',
    value => $exome_model, 
);
ok($i2, "add a exome model to it");

my $i3 = $m->add_input(
    name => 'tumor_rnaseq_model',
    value => $tumor_rnaseq_model, 
);
ok($i3, "add a tumor rnaseq model to it");

# this will prevent disk allocation during build initiation
# we will have to turn this off if the tasks in this pipeline spread to other machines
my $temp_dir = Genome::Sys->create_temp_directory("dummy-clinseq-build-dir");

my $b = $m->add_build(
    data_directory => $temp_dir,
);
ok($b, "created a new build");

my $common_name = $b->common_name;
my $expected_common_name = $m->expected_common_name;
is($common_name, $expected_common_name, "common name $common_name on build matches expected $expected_common_name");

my @errors = $b->validate_for_start;
is(scalar(@errors), 0, "build is valid to start")
    or diag(join("\n",@errors));
my $wf = $b->_initialize_workflow("inline");
ok($wf, "workflow validates");

# here perform checks on our file accessors
# using the newly created build to verify that these exist
# first create a build with a data directory of the expected test results dir
#
{
my $b2 = Genome::Model::Build::Command::DiffBlessed::blessed_build('apipe-test-clinseq-wer', '5.10' ) or die "Unable to grab blessed clinseq build";
my $patient_name = $b2->common_name or die "Unable to grab a common name for blessed clinseq build";
my $data_dir = $b2->data_directory or die "Unable to grab data_directory of blessed clinseq build";
is( Genome::Model::ClinSeq::->patient_dir($b2), $data_dir . "/$patient_name", "patient directory returned as expected" ) or die "Patient dir test failed. Aborting testing";
is( Genome::Model::ClinSeq::->snv_variant_source_file($b2,'wgs'), $data_dir . "/$patient_name/variant_source_callers/wgs/snv_sources.tsv", "wgs variant sources constructed as expected");
dies_ok( sub { Genome::Model::ClinSeq::->snv_variant_source_file($b2,'nonsense') },  "nonsense data source for variant source type dies as expected");
is( Genome::Model::ClinSeq::->clonality_dir($b2), $data_dir . "/$patient_name/clonality", "clonality directory returned as expected");
is( Genome::Model::ClinSeq::->varscan_formatted_readcount_file($b2), $data_dir . "/$patient_name/clonality/allsnvs.hq.novel.tier123.v2.bed.adapted.readcounts.varscan", "varscan counts returned as expected");
is( Genome::Model::ClinSeq::->cnaseq_hmm_file($b2), $data_dir . "/$patient_name/clonality/cnaseq.cnvhmm", "cnaseq file returned as expected");
}

done_testing()

