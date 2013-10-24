#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;

my $class = "Genome::File::Vcf::MetaInfoParser";
use_ok($class);

my @tests = (
    {
        input => "20130805",
        expected => ['20130805']
    },
    {
        input => "ftp://ftp.ncbi.nih.gov/genbank/genomes/Eukaryotes/vertebrates_mammals/Homo_sapiens/GRCh37/special_requests/GRCh37-lite.fa.gz",
        expected => ['ftp://ftp.ncbi.nih.gov/genbank/genomes/Eukaryotes/vertebrates_mammals/Homo_sapiens/GRCh37/special_requests/GRCh37-lite.fa.gz'],
    },
    {
        input => "<ID=TCGA-A2-A0CO-01A-13D-A228-09,SampleUUID=36053173-6839-43ec-8157-75d729085e6b,SampleTCGABarcode=TCGA-A2-A0CO-01A-13D-A228-09,File=TCGA-A2-A0CO-01A-13D-A228-09.bam,Platform=Illumina,Source=dbGap,Accession=phs000178>",
        expected => {
            ID => "TCGA-A2-A0CO-01A-13D-A228-09",
            SampleUUID => "36053173-6839-43ec-8157-75d729085e6b",
            SampleTCGABarcode => "TCGA-A2-A0CO-01A-13D-A228-09",
            File => "TCGA-A2-A0CO-01A-13D-A228-09.bam",
            Platform => "Illumina",
            Source => "dbGap",
            Accession => "phs000178",
        }
    },
    {
        input => "<InputVCFSource=<Samtools>>",
        expected => {
            InputVCFSource => {
                Samtools => 1
            }
        }
    },
    {
        input => "<ID=SS,Number=1,Type=Integer,Description=\"Variant status relative to non-adjacent Normal,0=wildtype,1=germline,2=somatic,3=LOH,4=post-transcriptional modification,5=unknown\">",
        expected => {
            ID => "SS",
            Number => "1",
            Type => "Integer",
            Description => "Variant status relative to non-adjacent Normal,0=wildtype,1=germline,2=somatic,3=LOH,4=post-transcriptional modification,5=unknown",
        }
    },
    {
        input => "<ID=MQ,Number=1,Type=Integer,Description=\"Phred style probability score that the variant is novel with respect to the genome\'s ancestor\">",
        expected => {
            ID => "MQ",
            Number => "1",
            Type => "Integer",
            Description => "Phred style probability score that the variant is novel with respect to the genome\'s ancestor",
        }
    },
);

for my $test (@tests) {
    my $input = $test->{input};
    my $expected = $test->{expected};
    my $output = $class->parse($input);
    ok($output, "Output created") or diag("Parsing failed for input: $input");
    is_deeply($output, $expected, "Input parsed as expected")
        or diag("Input: $input\nExpected: " .Data::Dumper::Dumper($expected) . "Got: ". Data::Dumper::Dumper($output));
}

done_testing;
