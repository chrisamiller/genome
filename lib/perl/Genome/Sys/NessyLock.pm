package Genome::Sys::NessyLock;

use strict;
use warnings;

use Carp qw(carp croak);
use Sys::Hostname qw(hostname);

use Genome::Sys;
use base 'UR::ModuleBase';   # *_message methods, but no constructor

my %NESSY_LOCKS_TO_REMOVE;
my $LOCKING_CLIENT;

sub lock {
    my($self, %args) = @_;

    $self->_start_locking_client;
    return 1 unless $LOCKING_CLIENT;

    my %user_data;
    @user_data{'host','pid','lsf_id','user'}
        = (hostname, $$, ($ENV{'LSB_JOBID'} || 'NONE'), Genome::Sys->username);

    my $resource_lock = $args{resource_lock};

    if ($self->_is_holding_nessy_lock($resource_lock)) {
        $self->error_message("Tried to lock resource more than once: $resource_lock");
        Carp::croak($self->error_message);
    }

    my $timeout = $self->_new_style_lock_timeout_from_args(%args);
    my $wait_announce_interval = delete $args{wait_announce_interval};
    unless (defined $wait_announce_interval) {
        croak('wait_announce_interval not defined');
    }

    my $info_content = join("\n", map { $_ . ': ' . $user_data{$_} } keys %user_data);
    my $claim_warning = '';
    my $initial_time = time();
    my $wait_announce_timer = AnyEvent->timer(
        after => $wait_announce_interval,
        interval => $wait_announce_interval,
        cb => sub {
            my $total_elapsed_time = time() - $initial_time;
            $self->status_message("waiting (total_elapsed_time = $total_elapsed_time seconds) on lock for resource '$resource_lock': $claim_warning. lock_info is:\n$info_content");
        },
    );
    my $claim = $LOCKING_CLIENT->claim($resource_lock, timeout => $timeout, user_data => \%user_data);
    undef $wait_announce_timer;
    $NESSY_LOCKS_TO_REMOVE{$resource_lock} = $claim if $claim;
    return $claim;
}

sub unlock {
    my($self, %args) = @_;

    my $resource_lock = delete $args{resource_lock};
    unless ($resource_lock) {
        carp('resource_lock is not set');
    }

    if ($LOCKING_CLIENT) {
        my $claim = delete $NESSY_LOCKS_TO_REMOVE{$resource_lock};
        if ($claim) {
            $claim->release;
        } else {
            $self->error_message("Nessy tried to release, but no claim in slot for resource_lock: $resource_lock");
        }
    } else {
        return 1;
    }
}

# clear_state() can be used after fork() to get a "clean" lock state.
sub clear_state {
    %NESSY_LOCKS_TO_REMOVE = ();
    undef $LOCKING_CLIENT;
}

sub is_enabled {
    return $ENV{GENOME_NESSY_SERVER} ? 1 : 0;
}

sub _start_locking_client {
    my $class = shift;

    if ($ENV{GENOME_NESSY_SERVER} and ! $LOCKING_CLIENT) {
        require Nessy::Client;
        $LOCKING_CLIENT = Nessy::Client->new(url => $ENV{GENOME_NESSY_SERVER});
    }
}

sub has_lock { _is_holding_nessy_lock(@_) }
sub _is_holding_nessy_lock {
    my($self, $resource_lock) = @_;
    return $NESSY_LOCKS_TO_REMOVE{$resource_lock};
}

sub min_timeout {
    return 5;
}

sub _new_style_lock_timeout_from_args {
    my($self, %args) = @_;

    my $block_sleep = delete $args{block_sleep} || 0;

    my $max_try = delete $args{max_try} || 0;

    my $min_timeout = min_timeout();
    my $timeout = $max_try * $block_sleep;
    unless ($timeout > $min_timeout) {
        $timeout = $min_timeout;
        carp("increasing timeout to minimum ($min_timeout)");
    }

    return $timeout;
}

sub release_all {
    my $class = shift;

    foreach my $resource_lock ( keys %NESSY_LOCKS_TO_REMOVE ) {
        warn("Removing remaining lock: '$resource_lock'") unless $ENV{'HARNESS_ACTIVE'};
        __PACKAGE__->unlock($resource_lock); # NessyLock
    }
    %NESSY_LOCKS_TO_REMOVE = ();
    undef $LOCKING_CLIENT;
}

UR::Context->process->add_observer(
    aspect => 'sync_databases',
    callback => sub {
        my($ctx, $aspect, $sync_db_result) = @_;
        if ($sync_db_result) {
            use vars '@CARP_NOT';
            local @CARP_NOT = (@CARP_NOT, 'UR::Context');
            foreach my $claim (values %NESSY_LOCKS_TO_REMOVE ) {
                $claim->validate
                    || Carp::croak(sprintf('Claim %s failed to verify during commit', $claim->resource_name));
            }
        }
    }
);

1;
