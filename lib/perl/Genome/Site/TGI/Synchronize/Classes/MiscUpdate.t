#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
};

use strict;
use warnings;

use above 'Genome';

use Test::More;

use_ok('Genome::Site::TGI::Synchronize::Classes::MiscUpdate') or die;

my $cnt = 0;

# Valid
my $taxon = Genome::Taxon->__define__(id => -100, name => '__TEST_TAXON__');
my $misc_update = Genome::Site::TGI::Synchronize::Classes::MiscUpdate->__define__(
    subject_class_name => 'test.organism_taxon',
    subject_id => $taxon->id,
    subject_property_name => 'estimated_organism_genome_size',
    editor_id => 'lims',
    edit_date => '2000-01-01 00:00:'.sprintf('%02d', $cnt++),
    old_value => undef,
    new_value => 1_000,
    description => 'UPDATE',
    is_reconciled => 0,
);
ok($misc_update, 'Define misc update');
is($misc_update->lims_table_name, 'organism_taxon', 'Correct lims table name');
my $genome_class_name = $misc_update->genome_class_name;
is($genome_class_name, 'Genome::Taxon', 'Correct genome class name');
my $genome_entity = $misc_update->genome_entity;
ok($genome_entity, 'Got genome entity');
is($genome_entity->class, $genome_class_name, 'Correct genome entity class name');
is($genome_entity->id, $taxon->id, 'Correct genome entity id');
ok($misc_update->perform_update, 'Perform update');
is($misc_update->result, 'PASS', 'Correct result after update');
is($misc_update->status, "PASS	UPDATE	test.organism_taxon	-100	estimated_organism_genome_size	'NA'	'NULL'	'1000'", 'Correct status after update');
ok($misc_update->is_reconciled, 'Is reconciled');
ok(!$misc_update->error_message, 'No error after update');
is($taxon->estimated_genome_size, 1000, 'Set estimated_genome_size on taxon');

# Invalid genome class
$misc_update = Genome::Site::TGI::Synchronize::Classes::MiscUpdate->__define__(
    subject_class_name => 'test.blah',
    subject_id => -100,
    subject_property_name => 'name',
    editor_id => 'lims',
    edit_date => '2000-01-01 00:00:'.sprintf('%02d', $cnt++),
    old_value => undef,
    new_value => undef,
    description => 'UPDATE',
    is_reconciled => 0,
);
ok(!$misc_update->genome_class_name, 'Failed to get genome class name for invalid subject class name');
my $error_message = $misc_update->error_message;
is($error_message, 'No genome class name for lims table name => blah', 'Correct error msg');

# No obj for subject id
$misc_update = Genome::Site::TGI::Synchronize::Classes::MiscUpdate->__define__(
    subject_class_name => 'test.organism_taxon',
    subject_id => -10000,
    subject_property_name => 'name',
    editor_id => 'lims',
    edit_date => '2000-01-01 00:00:'.sprintf('%02d', $cnt++),
    old_value => undef,
    new_value => undef,
    description => 'UPDATE',
    is_reconciled => 0,
);
ok(!$misc_update->genome_entity, 'Failed to get genome entity for invalid id');
$error_message = $misc_update->error_message;
is($error_message, 'Failed to get Genome::Taxon for id => -10000', 'Correct error msg');

# Invalid subject class name
$misc_update = Genome::Site::TGI::Synchronize::Classes::MiscUpdate->__define__(
    subject_class_name => '.',
    subject_id => $taxon->id,
    subject_property_name => 'name',
    editor_id => 'lims',
    edit_date => '2000-01-01 00:00:'.sprintf('%02d', $cnt++),
    old_value => undef,
    new_value => undef,
    description => 'UPDATE',
    is_reconciled => 0,
);
ok(!$misc_update->lims_table_name, 'Failed to get lims table name invalid subject class name');
$error_message = $misc_update->error_message;
is($error_message, 'Failed to get schema from subject class name => .', 'Correct error msg');

# Invalid subject class name
$misc_update = Genome::Site::TGI::Synchronize::Classes::MiscUpdate->__define__(
    subject_class_name => 'schema.',
    subject_id => $taxon->id,
    subject_property_name => 'name',
    editor_id => 'lims',
    edit_date => '2000-01-01 00:00:'.sprintf('%02d', $cnt++),
    old_value => undef,
    new_value => undef,
    description => 'UPDATE',
    is_reconciled => 0,
);
ok(!$misc_update->lims_table_name, 'Failed to get lims table name from invalid subject class name.');
$error_message = $misc_update->error_message;
is($error_message, 'Failed to get lims table name from subject class name => schema.', 'Correct error msg');

# PERFORM UPDATE FAILS
# Invalid subject class name
$misc_update = Genome::Site::TGI::Synchronize::Classes::MiscUpdate->__define__(
    subject_class_name => 'schema.org',
    subject_id => $taxon->id,
    subject_property_name => 'name',
    editor_id => 'lims',
    edit_date => '2000-01-01 00:00:'.sprintf('%02d', $cnt++),
    old_value => '__TEST_TAXON__',
    new_value => '__NEW_NAME__',
    description => 'UPDATE',
    is_reconciled => 0,
);
ok(!$misc_update->perform_update, 'Failed to perform update for invalid subject class name');
$error_message = $misc_update->error_message;
is($misc_update->result, 'FAIL', 'Correct result (FAIL) after update');
is($misc_update->status, "FAIL	UPDATE	schema.org	-100	name	'NA'	'__TEST_TAXON__'	'__NEW_NAME__'", 'Correct status after update');
is($error_message, 'Unsupported LIMS table name => org', 'Correct error msg');
ok(!$misc_update->is_reconciled, 'Is not reconciled');

# Old value not the same as current value
$misc_update = Genome::Site::TGI::Synchronize::Classes::MiscUpdate->__define__(
    subject_class_name => 'test.organism_taxon',
    subject_id => $taxon->id,
    subject_property_name => 'estimated_organism_genome_size',
    editor_id => 'lims',
    edit_date => '2000-01-01 00:00:'.sprintf('%02d', $cnt++),
    old_value => 'not the same as the current value',
    new_value => 10_000,
    description => 'UPDATE',
    is_reconciled => 0,
);
ok($misc_update, 'Define misc update');
ok(!$misc_update->perform_update, 'Failed to perform update');
is($misc_update->result, 'FAIL', 'Correct result (FAIL) after update');
is($misc_update->status, "FAIL	UPDATE	test.organism_taxon	-100	estimated_organism_genome_size	'1000'	'not the same as the current value'	'10000'", 'Correct status after update');
is($misc_update->error_message, 'Current APipe value (1000) does not match the LIMS old value (not the same as the current value)!', 'Correct error after update');
ok(!$misc_update->is_reconciled, 'Is not reconciled');
is($taxon->estimated_genome_size, 1000, 'Did not alter estimated_genome_size on taxon');

# PERFORM UPDATE SKIP
# Unsupported lims attr
$misc_update = Genome::Site::TGI::Synchronize::Classes::MiscUpdate->__define__(
    subject_class_name => 'test.organism_taxon',
    subject_id => $taxon->id,
    subject_property_name => 'next_amplicon_iteration',
    editor_id => 'lims',
    edit_date => '2000-01-01 00:00:'.sprintf('%02d', $cnt++),
    old_value => 'not the same as the current value',
    new_value => 10_000,
    description => 'UPDATE',
    is_reconciled => 0,
);
ok($misc_update, 'Define misc update');
ok($misc_update->perform_update, 'Failed to perform update');
is($misc_update->result, 'SKIP', 'Correct result (SKIP) after update');
is($misc_update->status, "SKIP	UPDATE	test.organism_taxon	-100	next_amplicon_iteration	'NA'	'not the same as the current value'	'10000'", 'Correct status after update');
ok(!$misc_update->is_reconciled, 'Is not reconciled');

done_testing();
exit;

