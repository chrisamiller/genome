package Genome::Config::Profile;

use strict;
use warnings;

use Genome;
use UR::Util;

use feature qw(switch);

class Genome::Config::Profile {
    is => 'UR::Object',
    is_transactional => 0,
    has => [
        config_rule_maps => {
            is_many => 1,
            is => 'Genome::Config::RuleModelMap'
        },
        analysis_project => {
            is => 'Genome::Config::AnalysisProject',
        },
    ]
};


sub create_from_analysis_project {
    my $class = shift;
    my $analysis_project = shift;

    my @config_rule_maps = map {
        Genome::Config::Translator->get_rule_model_map_from_config($_)
    } grep{ $_->status eq 'active' } $analysis_project->config_items;

    return $class->create(
        config_rule_maps => \@config_rule_maps,
        analysis_project => $analysis_project,
    );
}

sub get_config {
    my $self = shift;
    my $inst_data = shift;

    my @model_hashes = map { $_->models }
        grep { $_->match_and_concretize($inst_data) }
        $self->config_rule_maps;

    return $self->_merge_extra_parameters($self->_merge_model_hashes(@model_hashes));
}

sub _merge_model_hashes {
    my $self = shift;
    my @source_hashes = @_;

    my $destination_hash = {};

    for my $source (@source_hashes) {
        for my $key (keys %$source) {
            $destination_hash->{$key} ||= [];
            push @{$destination_hash->{$key}}, @{$source->{$key}};
        }
    }

    return UR::Util::deep_copy($destination_hash);
}

sub _merge_extra_parameters {
    my $self = shift;
    my $config_hash = shift;

    for my $model_config (values %$config_hash) {
        for (@$model_config) {
             $self->_add_user_if_not_present($_);
        }
    }

    return $config_hash;
}

sub _add_user_if_not_present {
    my $self = shift;
    my $hashref = shift;

    $hashref->{run_as} ||= $self->analysis_project->run_as;

    return 1;
}

sub prepare_configuration_hashes_for_instrument_data {
    my ($self, $instrument_data) = @_;

    my $config_hash = $self->get_config($instrument_data);

    for my $model_type (keys %$config_hash) {
        if (ref $config_hash->{$model_type} ne 'ARRAY') {
            $config_hash->{$model_type} = [$config_hash->{$model_type}];
        }

        for my $model_instance (@{$config_hash->{$model_type}}) {
            my $instrument_data_properties = delete $model_instance->{instrument_data_properties};
            if($instrument_data_properties) {
                while((my $model_property, my $instrument_data_property) = each %$instrument_data_properties) {
                    if (ref $instrument_data_property eq 'ARRAY') {
                        $model_instance->{$model_property} = [
                            grep { defined($_) }
                            map { $instrument_data->$_ }
                            @$instrument_data_property
                        ];
                    } else {
                        $model_instance->{$model_property} = $instrument_data->$instrument_data_property;
                    }
                }
            }
        }

        $config_hash->{$model_type} = $self->_process_mapped_samples($instrument_data, $config_hash->{$model_type}) if $model_type->requires_subject_mapping;
    }
    return $config_hash;
}

sub _process_mapped_samples {
    my ($self, $instrument_data, $model_hashes) = @_;
    die('Must provide an analysis project, a piece of instrument data and a config hash!')
        unless($instrument_data && $model_hashes);

    my @subject_mappings = Genome::Config::AnalysisProject::SubjectMapping->get(
        analysis_project => $self->analysis_project,
        subjects => $instrument_data->sample
    );

    unless (@subject_mappings) {
        die(sprintf('Found no mapping information for %s in project %s for a model type that requires mapping!',
            $instrument_data->__display_name__,
            $self->analysis_project->__display_name__));
    }

    return [ map {
        my $mapping = $_;
        my %tags = map { $_->id => 1 } $mapping->tags;
        map { {
          (map { $_->label => $_->subject } $mapping->subject_bridges),
          (map { $_->key => $_->value } $mapping->inputs),
          %$_
        } } grep { $self->_model_hash_matches_tags($_, \%tags) } @$model_hashes
    } @subject_mappings ];
}

sub _model_hash_matches_tags {
    my ($self, $model_hash, $tag_hash) = @_;

    my @model_hash_tags = $model_hash->{config_profile_item}->tags;
    if(keys %$tag_hash) {
        return List::MoreUtils::any { exists $tag_hash->{$_->id} } @model_hash_tags;
    } else {
        return !@model_hash_tags;
    }
}

1;

