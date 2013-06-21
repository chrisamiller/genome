package Genome::Sample::Command::Import::Manager;

use strict;
use warnings;

use Genome;

use Data::Dumper;
use Genome::Sample::Command::Import;
use IO::File;
use Switch;
use YAML;

class Genome::Sample::Command::Import::Manager {
    is => 'Command::V2',
    doc => 'Manage importing a group of samples including importing instrument data and creating and building models.',
    has => [
        working_directory => {
            is => 'Text',
            doc => 'Directory to read and write.',
        },
    ],
    has_optional => [
        make_progress => { 
            is => 'Boolean',
            default_value => 0,
            doc => 'Do not create samples, models, run imports and schedule builds. Only print the status.', 
        },
        # create_entities: samples, models
        # launch_inst_data_import: launch the inst data command
        # schedule_builds: schedule builds
    ],
    has_optional_calculated => [
        sample_csv_file => {
            calculate_from => 'working_directory',
            calculate => sub{ my $working_directory = shift; return $working_directory.'/samples.csv'; },
            doc => 'CSV file of samples and attributes. A column called "name" is required. The name should be dash (-) separated values of the nomenclature, indivdual id and sample id.',
        },
        config_file => {
            calculate_from => 'working_directory',
            calculate => sub{ my $working_directory = shift; return $working_directory.'/config.yaml'; },
        },
    ],
    has_optional_transient => [
        config => { is => 'Hash', },
        namespace => { is => 'Text', },
        samples => { is => 'Hash', },
        model_class => { is => 'Text' },
        model_params => { is => 'Hash' },
        instrument_data_import_command_format => { is => 'Text', },
        instrument_data_import_command_sample_name_cnt => { is => 'Number', },
    ],
};

sub execute {
    my $self = shift;

    my $samples = $self->_load_samples;
    return if not $samples;

    my $make_progress = $self->_make_progress;
    return if not $make_progress;

    $self->_status($samples);

    return 1;
}

sub __errors__ {
    my $self = shift;

    my @errors = $self->SUPER::__errors__;
    return @errors if @errors;

    if ( not -d $self->working_directory ) {
        push @errors, UR::Object::Tag->create(
            type => 'invalid',
            properties => [qw/ working_directory /],
            desc => 'Working directory does not exist or is not aq directory!',
        );
        return @errors;
    }

    my $config_error = $self->_load_config;
    if ( $config_error ) {
        push @errors, UR::Object::Tag->create(
            type => 'invalid',
            properties => [qw/ config_file /],
            desc => $config_error,
        );
        return @errors;
    }

    my $sample_csv_error = $self->_load_sample_csv_file;
    if ( $sample_csv_error ) {
        push @errors, UR::Object::Tag->create(
            type => 'invalid',
            properties => [qw/ sample_csv_file /],
            desc => $sample_csv_error,
        );
        return @errors;
    }

    my $model_params_error = $self->_resolve_model_params;
    if ( $model_params_error ) {
        push @errors, UR::Object::Tag->create(
            type => 'invalid',
            properties => [qw/ config_file /],
            desc => $model_params_error,
        );
        return @errors;
    }

    my $import_cmd_error = $self->_resolve_instrument_data_import_command;
    if ( $import_cmd_error ) {
        push @errors, UR::Object::Tag->create(
            type => 'invalid',
            properties => [qw/ config_file /],
            desc => $import_cmd_error,
        );
        return @errors;
    }

    return;
}

sub _load_config {
    my $self = shift;

    my $config_file = $self->config_file;
    if ( not -s $config_file ) {
        return 'Config file does not exist! '.$config_file;
    }

    my $config = YAML::LoadFile($config_file);
    if ( not $config ) {
        return 'Failed to load config file! '.$config_file;
    }
    $self->config($config);

    my $nomenclature = $config->{sample}->{nomenclature};
    if ( not $nomenclature ) {
        return 'No nomenclature in config file! '.$config_file;
    }

    my $namespace = Genome::Sample::Command::Import->namespace_for_nomenclature($nomenclature);
    if ( not $namespace ) {
        return 'Could not get namespace from miporter. Please ensure there is a config for the '.$nomenclature.' nomenclature.';
    }
    $self->namespace($namespace);

    return;
}

sub _load_sample_csv_file {
    my $self = shift;

    my $sample_csv_file = $self->sample_csv_file;
    if ( not -s $sample_csv_file ) {
        return 'Sample csv file does not exist! '.$sample_csv_file;
    }

    my $sample_csv_reader = Genome::Utility::IO::SeparatedValueReader->create(
        input => $sample_csv_file,
        separator => ',',
    );
    if ( not $sample_csv_reader ) {
        return 'Failed to open sample csv! '.$sample_csv_file;
    }

    my %headers_not_found = ( name => 1, source_files => 1, );
    for my $header ( @{$sample_csv_reader->headers} ) {
        delete $headers_not_found{$header};
    }

    if ( %headers_not_found ) {
        return 'No '.join(' ', map { '"'.$_.'"' } keys %headers_not_found).' column in sample csv! '.$self->sample_csv_file;
    }

    my @importer_property_names = Genome::Sample::Command::Import->importer_property_names_for_namespace($self->namespace);
    my %samples;
    while ( my $sample = $sample_csv_reader->next ) {
        my $name = delete $sample->{name};
        $samples{$name} = {
            name => $name,
            source_files => [ split(' ', delete $sample->{source_files}) ],
            importer_params => { name => $name, },
        };
        for my $attr ( sort keys %$sample ) {
            my $value = $sample->{$attr};
            next if not defined $value or $value eq '';
            if ( $attr =~ /^(sample|individual)\./ ) { # is sample/individual/inst data indicated?
                push @{$samples{$name}->{importer_params}->{$1.'_attributes'}}, $attr."='".$value."'";
            }
            elsif ( $attr =~ s/^instrument_data\.// ) { # inst data attr
                push @{$samples{$name}->{'instrument_data_attributes'}}, $attr."='".$value."'";
            }
            elsif ( grep { $attr eq $_ } @importer_property_names ) { # is the attr specified in the importer?
                $samples{$name}->{importer_params}->{$attr} = $value;
            }
            else { # assume sample attribute
                push @{$samples{$name}->{importer_params}->{'sample_attributes'}}, $attr."='".$value."'";
            }
        }
    }
    $self->samples(\%samples);

    return;
}

sub _resolve_model_params {
    my $self = shift;

    my $config = $self->config;
    if ( not $config->{model} ) {
        return 'No model info in config! '.$config;
    }

    my %model_params;
    for my $name ( keys %{$config->{model}} ) {
        $model_params{$name} = $config->{model}->{$name};
    }

    if ( not $model_params{processing_profile_id} ) {
        return 'No processing profile id for model in config! '.Data::Dumper::Dumper($config->{model});
    }
    my $processing_profile_id = delete $model_params{processing_profile_id};
    $model_params{processing_profile} = Genome::ProcessingProfile->get($processing_profile_id);
    if ( not $model_params{processing_profile} ) { 
        return 'Failed to get processing profile for id! '.$processing_profile_id;
    }

    my @processing_profile_class_parts = split('::', $model_params{processing_profile}->class);
    my $model_class = join('::', $processing_profile_class_parts[0], 'Model', $processing_profile_class_parts[2]);
    my $model_meta = $model_class->__meta__;
    if ( not $model_meta ) {
        return 'Failed to get model class meta! '.$model_class;
    }

    for my $param_name ( keys %model_params ) {
        next if $param_name !~ s/_id$//;
        my $param_value_id = delete $model_params{$param_name.'_id'};
        my $param_property = $model_meta->property_meta_for_name($param_name);
        return "Failed to get '$param_name' property from model class! ".$model_class if not $param_property;
        my $param_value_class = $param_property->data_type;
        my $param_value = $param_value_class->get($param_value_id);
        return "Failed to get $param_value_class for id! $param_value_id" if not $param_value;
        $model_params{$param_name} = $param_value;
    }

    $self->model_class($model_class);
    $self->model_params(\%model_params);

    return;
}

sub _resolve_instrument_data_import_command {
    my $self = shift;

    my $cmd_format;
    my @sample_name_replaces_in_command;
    if ( $cmd_format = $self->config->{'job dispatch'}->{launch} ) {
        @sample_name_replaces_in_command = $cmd_format =~ /\%s/g;
        if ( not @sample_name_replaces_in_command ) {
            return 'No "%s" in job dispatch config to replace with sample name! '.$cmd_format;
        }
        $cmd_format .= ' ';
    }
    $self->instrument_data_import_command_sample_name_cnt(scalar @sample_name_replaces_in_command);
    $cmd_format .= 'genome instrument-data import basic --sample name=%s --source-files %s --import-source-name %s%s',
    $self->instrument_data_import_command_format($cmd_format);

    return;
}

sub _load_samples {
    my $self = shift;

    my $samples = $self->samples;
    my %instrument_data = map { $_->sample->name, $_ } Genome::InstrumentData::Imported->get(
        original_data_path => [ map { join(',', @{$_->{source_files}}) } values %$samples ],
        '-hint' => [qw/ attributes /],
    );

    my $model_class = $self->model_class;
    my $model_params = $self->model_params;
    for my $name ( keys %$samples ) {
        # Inst Data
        my $instrument_data = $instrument_data{$name};
        $samples->{$name}->{instrument_data} = $instrument_data;
        $samples->{$name}->{instrument_data_file} = eval{
            my $attribute = $instrument_data->attributes(attribute_label => 'bam_path');
            if ( not $attribute ) {
                $attribute = $instrument_data->attributes(attribute_label => 'archive_path');
            }
            return $attribute->attribute_value if $attribute;
        };

        # Sample
        my $genome_sample = Genome::Sample->get(name => $name);
        $samples->{$name}->{sample} = $genome_sample;

        # Model
        if ( $genome_sample ) {
            $model_params->{subject} = $genome_sample;
            my $model = $model_class->get(%$model_params);
            $samples->{$name}->{model} = $model;
            $samples->{$name}->{build} = $model->latest_build if $model;
        }

        # Status
        $self->set_sample_status($samples->{$name});
    }

    $self->samples($samples);
    return 1;
}

sub _set_job_status_to_samples {
    my $self = shift;

    my $samples = $self->samples;
    Carp::confess('Need samples to load job status!') if not $samples;

    return 1 if not $self->config->{'job dispatch'};

    my $job_list_cmd = $self->config->{'job dispatch'}->{list}->{'command'};
    if ( not $job_list_cmd ) {
        $self->error_message('No job list "command" in config! '.YAML::Dump($self->config));
        return;
    }

    my $name_column = $self->config->{'job dispatch'}->{list}->{'name column'};
    if ( not $name_column ) {
        $self->error_message('No job list "name column" in config! '.YAML::Dump($self->config));
        return;
    }
    $name_column--;

    my $status_column = $self->config->{'job dispatch'}->{list}->{'status column'};
    if ( not $status_column ) {
        $self->error_message('No job list "status column" in config! '.YAML::Dump($self->config));
        return;
    }
    $status_column--;

    $job_list_cmd .= ' 2>/dev/null |';
    my $fh = IO::File->new($job_list_cmd);
    while ( my $line = $fh->getline ) {
        my @tokens = split(/\s+/, $line);
        my $name = $tokens[ $name_column ];
        next if not $samples->{$name};
        $samples->{$name}->{job_status} = lc $tokens[ $status_column ];
    }

    return 1;
}

sub _create_sample {
    my ($self, $importer_params) = @_;

    Carp::confess('No params to create sample!') if not $importer_params;

    local $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 0; # quiet the importer
    my $importer_class_name = Genome::Sample::Command::Import->importer_class_name_for_namespace($self->namespace);
    my $importer = $importer_class_name->create(%$importer_params);
    if ( not $importer ) {
        $self->error_message('Failed to create sample importer for sample! '.Data::Dumper::Dumper($importer_params));
        return;
    }
    if ( not $importer->execute ) {
        $self->error_message('Failed to execute sample importer for sample! '.Data::Dumper::Dumper($importer_params));
        return;
    }
    my $sample = $importer->_sample;
    if ( not $sample ) {
        $self->error_message('Executed the importer successfully, but failed to create sample!');
        return;
    }

    return $sample;
}

sub set_sample_status {
    my ($self, $sample) = @_;

    Carp::confess('No sample to set status!') if not $sample;

    $sample->{status} = eval{
        return 'sample_needed' if not $sample->{sample};
        return 'import_'.$sample->{job_status} if $sample->{job_status};
        return 'import_needed' if not $sample->{instrument_data};
        return 'import_failed' if not defined $sample->{instrument_data_file} or not -s $sample->{instrument_data_file};
        return 'model_needed' if $sample->{instrument_data} and not $sample->{model};
        return 'build_requested' if $sample->{model}->build_requested;
        return 'build_needed' if not $sample->{build};
        return 'build_'.lc($sample->{build}->status);
    };

    return $sample->{status};
}

sub _status {
    my $self = shift;

    my $set_job_status_to_samples = $self->_set_job_status_to_samples;
    return if not $set_job_status_to_samples;

    my %totals;
    my $status;
    for my $sample ( sort { $a->{name} cmp $b->{name} } values %{$self->samples} ) {
        $self->set_sample_status($sample);
        $totals{total}++;
        $self->set_sample_status($sample);
        $totals{ $sample->{status} }++;
        $totals{build}++ if $sample->{status} =~ /^build/;
        $status .= sprintf(
            "%-20s %-15s %s %s %s %s\n",
            $sample->{name},
            $sample->{status}, 
            ( $sample->{instrument_data} ? $sample->{instrument_data}->id : 'NA' ),
            ( $sample->{model} ? $sample->{model}->id : 'NA' ),
            ( $sample->{build} ? ( $sample->{build}->id, $sample->{build}->status ) : ( 'NA', 'NA' ) ),
        );
    }
    print "$status\nSummary:\n".join("\n", map { sprintf('%-16s %s', $_, $totals{$_}) } sort { $a cmp $b } keys %totals)."\n";
    return 1;
}

sub _resolve_instrument_data_import_command_for_sample {
    my ($self, $sample) = @_;

    Carp::confess('No samples to resolved instrument data import command!') if not $sample;

    my $sample_name_cnt = $self->instrument_data_import_command_sample_name_cnt;
    my @sample_name_replaces;
    for (1..$sample_name_cnt) { push @sample_name_replaces, $sample->{name}; }

    my $cmd .= sprintf(
        $self->instrument_data_import_command_format,
        @sample_name_replaces,
        $sample->{name},
        join(',', @{$sample->{source_files}}),
        $self->config->{sample}->{nomenclature},
        ( 
            $sample->{instrument_data_attributes}
            ? ' --instrument-data-properties '.join(',', @{$sample->{instrument_data_attributes}})
            : ''
        ),
    );

    return $cmd;
}

sub _make_progress {
    my $self = shift;

    return 1 if not $self->make_progress;

    my $set_job_status_to_samples = $self->_set_job_status_to_samples;
    return if not $set_job_status_to_samples;

    my $model_class = $self->model_class;
    my $model_params = $self->model_params;
    for my $sample ( values %{$self->samples} ) {
        # Create sample
        if ( not $sample->{sample} ) {
            $sample->{sample} = $self->_create_sample($sample->{importer_params});
            return if not $sample->{sample};
        }

        # Create model
        $model_params->{subject} = $sample->{sample};
        my $model = $sample->{model};
        if ( not $model ) {
            $model = $model_class->create(%$model_params);
            return if not $model;
            $sample->{model} = $model;
        }

        # Model should have instrument data
        my $instrument_data = $sample->{instrument_data};
        if ( $instrument_data ) {
            my @model_instrument_data = $model->instrument_data;
            if ( not @model_instrument_data or not grep { $instrument_data->id eq $_ } map { $_->id } @model_instrument_data ) {
                $model->add_instrument_data($instrument_data);
            }
            $sample->{build} = $model->latest_build;
        }

        # Run import command, or schedaule build
        if ( $sample->{status} eq 'import_needed' ) {
            my $launch_ok = $self->_launch_instrument_data_import_for_sample($sample);
            return if not $launch_ok;
        }
        elsif ( $sample->{status} eq 'import_failed' ) {
            $sample->{instrument_data}->delete if $sample->{instrument_data};
            my $launch_ok = $self->_launch_instrument_data_import_for_sample($sample);
            return if not $launch_ok;
        }
        elsif ( $sample->{status} eq 'build_needed'
            #or $sample->{status} eq 'build_failed'
            or $sample->{status} eq 'build_abandoned'
            or $sample->{status} eq 'build_unstartable'
        ) {
            $sample->{model}->build_requested(1);
            $sample->{build} = undef;
        }
    }

    return 1;
}

sub _launch_instrument_data_import_for_sample {
    my ($self, $sample) = @_;
    Carp::confess('No sample to _resolve_instrument_data_import_command_for_sample!') if not $sample;
    my $cmd = $self->_resolve_instrument_data_import_command_for_sample($sample);
    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
    return 1 if $rv;
    $self->error_message($@) if $@;
    $self->error_message('Failed to launch instrument data import command!');
    return;
}

1;

