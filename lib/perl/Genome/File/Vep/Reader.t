#!/usr/bin/env perl

use above 'Genome';
use Test::More;

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

my $pkg = "Genome::File::Vep::Reader";

use_ok($pkg);

# NOTE: this data is "clean".
my $vep_fh = new IO::String(<<EOS
#Uploaded_variation	Location	Allele	Gene	Feature	Feature_type	Consequence	cDNA_position	CDS_position	Protein_position	Amino_acids	Codons	Existing_variation	Extra
HELLO1_1_10_A_T	1:10	T	GENE1	TS1	Transcript	NON_SYNONYMOUS_CODING	3	3	1	D/V	gAt/gTt	-	EX1=e1;HGNC=HELLO1
HELLO2_1_20_G_A	1:20	A	GENE2	TS2	Transcript	STOP_GAINED	6	6	2	W/*	tgG/tgA	-	HGNC=HELLO2
#COMMENTED	1:20	A	GENE2	TS2	Transcript	STOP_GAINED	6	6	2	W/*	tgG/tgA	-	HGNC=HELLO2
HELLO3_3_20_G_A	3:20	A	GENE3	TS3	Transcript	STOP_GAINED	6	6	2	W/*	tgG/tgA	-	HGNC=HELLO2
HELLO4_4_20_G_A	4:20	A	GENE4	TS4	Transcript	STOP_GAINED	6	6	2	W/*	tgG/tgA	-	HGNC=HELLO2;PolyPhen=possibly_damaging(0.6);Condel=neutral(0.1);SIFT=tolerated(0.2)
EOS
);

my $reader = $pkg->fhopen($vep_fh);
ok($reader, "Created reader");
ok($reader->{header}, "got header");
my $entry = $reader->next;
ok($entry, "Read entry");
is($entry->{chrom}, "1", "entry chrom");
is($entry->{position}, "10", "entry pos");
is($entry->{allele}, "T", "entry allele");

$entry = $reader->peek;
ok($entry, "peek at entry 2");
is($entry->{uploaded_variation}, "HELLO2_1_20_G_A", "uploaded_variant");

ok($entry = $reader->next, "got next entry");
ok($entry, "get entry 2 after peek");
is($entry->{uploaded_variation}, "HELLO2_1_20_G_A", "uploaded_variant");

$reader->add_filter(sub {
    my $entry = shift;
    return if !exists $entry->{extra}->{PolyPhen};
    return 1;
});

ok($entry = $reader->next, "got next entry");
is($entry->{uploaded_variation}, "HELLO4_4_20_G_A", "filtered next skips unwanted entries");

ok(!$reader->next, "next at EOF yields undef");

done_testing();


