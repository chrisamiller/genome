package Genome::Site::TGI::Command::ImportDataForWorkOrder;

use strict;
use warnings;

use Genome;

class Genome::Site::TGI::Command::ImportDataForWorkOrder {
    is => 'Command::V2',
    has_input => [
        work_order_id => {
            is => 'Text',
            doc => 'The ID of the work order to import',
        },
    ],
};

sub execute {
    my $self = shift;

    my $wo = $self->_resolve_work_order;
    my @items = $self->_resolve_items;

    my @existing = Genome::InstrumentData->get(id => [map $_->entity_id, @items]);

    $self->status_message(
        'Work Order has %s instrument data of which %s are already present.',
        scalar(@items),
        scalar(@existing),
    );

    my %found;
    $found{$_->id}++ for @existing;
    my @to_import = grep { !$found{$_->entity_id} } @items;

    my @ii = Genome::Site::TGI::Synchronize::Classes::IndexIllumina->get(id => [map $_->entity_id, @to_import]);
    $self->_import_indexillumina($_) for @ii;

    return 1;
}

sub _resolve_work_order {
    my $self = shift;
    my $wo_id = $self->work_order_id;

    my $existing_project = Genome::Project->get($wo_id);
    unless ($existing_project) {
        my $wo = Genome::Site::TGI::Synchronize::Classes::LimsProject->get($wo_id);
        unless ($wo) {
            $self->fatal_message('No work order found for ID %s', $wo_id);
        }

        $existing_project = $wo->create_in_genome;
    }

    return $existing_project;
}

sub _resolve_items {
    my $self = shift;

    my @existing_items = Genome::ProjectPart->get(
        label => 'instrument_data',
        project_id => $self->work_order_id,
    );

    my @importable_items = Genome::Site::TGI::Synchronize::Classes::LimsProjectInstrumentData->get(
        project_id => $self->work_order_id,
    );

    my %found;
    $found{$_->entity_id}++ for @existing_items;
    my @to_import = grep { !$found{$_->entity_id} } @importable_items;

    for my $item (@to_import) {
        push @existing_items, $item->create_in_genome;
    }

    return @existing_items;
}

sub _import_indexillumina {
    my $self = shift;
    my $ii = shift;

    my $existing_library = Genome::Library->get($ii->library_id);
    unless ($existing_library) {
        my $ls = Genome::Site::TGI::Synchronize::Classes::LibrarySummary->get($ii->library_id);
        $self->_import_librarysummary($ls);
    }

    $ii->create_in_genome;
}

sub _import_librarysummary {
    my $self = shift;
    my $ls = shift;

    my $existing_sample = Genome::Sample->get($ls->sample_id);
    unless ($existing_sample) {
        my $os = Genome::Site::TGI::Synchronize::Classes::OrganismSample->get($ls->sample_id);
        $self->_import_organismsample($os);
    }

    $ls->create_in_genome;
}

sub _import_organismsample {
    my $self = shift;
    my $os = shift;

    my $existing_individual = Genome::Individual->get($os->source_id);
    unless ($existing_individual) {
        my $oi = Genome::Site::TGI::Synchronize::Classes::OrganismIndividual->get($os->source_id);
        $self->_import_organismindividual($oi);
    }

    $os->create_in_genome;
}

sub _import_organismindividual {
    my $self = shift;
    my $oi = shift;

    my $existing_taxon = Genome::Taxon->get($oi->taxon_id);
    unless ($existing_taxon) {
        my $ot = Genome::Site::TGI::Synchronize::Classes::OrganismTaxon->get($oi->taxon_id);
        $self->_import_organismtaxon($ot);
    }

    $oi->create_in_genome;
}

sub _import_organismtaxon {
    my $self = shift;
    my $ot = shift;

    $ot->create_in_genome;
}

1;