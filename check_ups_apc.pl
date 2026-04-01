#!/usr/bin/env perl
# nagios: -epn
# icinga: -epn
#
# check_ups_apc.pl
# Basic APC UPS monitor for Nagios/Icinga via SNMP.
#
# License: GNU GPL v2.0

use strict;
use warnings;
use feature ':5.10';

use Getopt::Long qw(:config no_ignore_case bundling);
use Net::SNMP;

my $script = 'check_ups_apc.pl';
my $script_version = '2.0.0';

# Defaults
my $host = '';
my $version = 2;
my $community = 'public';

my $username = '';
my $auth_password = '';
my $auth_protocol = 'sha';
my $priv_password = '';
my $priv_protocol = 'aes';

my $warn_capacity = 50;
my $crit_capacity = 25;
my $warn_load = 70;
my $crit_load = 80;
my $warn_temp = 35;
my $crit_temp = 45;

my $help = 0;

GetOptions(
    'host|H=s'         => \$host,
    'version|v=i'      => \$version,
    'community|C=s'    => \$community,
    'username|U=s'     => \$username,
    'authpassword|A=s' => \$auth_password,
    'authprotocol|a=s' => \$auth_protocol,
    'privpassword|X=s' => \$priv_password,
    'privprotocol|x=s' => \$priv_protocol,

    'warn-capacity=i'  => \$warn_capacity,
    'crit-capacity=i'  => \$crit_capacity,
    'warn-load=i'      => \$warn_load,
    'crit-load=i'      => \$crit_load,
    'warn-temp=i'      => \$warn_temp,
    'crit-temp=i'      => \$crit_temp,

    'help|h|?'         => \$help,
) or usage(3, 'UNKNOWN - Invalid arguments');

usage(0) if $help;
usage(3, 'UNKNOWN - Missing required -H/--host') if !$host;

# OIDs
my %oids = (
    model            => '.1.3.6.1.4.1.318.1.1.1.1.1.1.0',
    battery_capacity => '.1.3.6.1.4.1.318.1.1.1.2.2.1.0',
    output_status    => '.1.3.6.1.4.1.318.1.1.1.4.1.1.0',
    output_load      => '.1.3.6.1.4.1.318.1.1.1.4.2.3.0',
    batt_temp        => '.1.3.6.1.4.1.318.1.1.1.2.2.2.0',
    remaining_time   => '.1.3.6.1.4.1.318.1.1.1.2.2.3.0',
    battery_replace  => '.1.3.6.1.4.1.318.1.1.1.2.2.4.0',
);

my ($session, $error) = create_snmp_session();
if (!$session) {
    print "CRITICAL - SNMP session error: $error\n";
    exit 2;
}

my $result = $session->get_request(-varbindlist => [ values %oids ]);
if (!defined $result) {
    my $err = $session->error();
    $session->close();
    print "CRITICAL - SNMP query failed: $err\n";
    exit 2;
}

$session->close();

my $status = 0;
my @parts;
my @perf;

my $model = $result->{$oids{model}} // 'APC UPS';
push @parts, $model;

my $capacity = to_num($result->{$oids{battery_capacity}});
if (defined $capacity) {
    if ($capacity < $crit_capacity) {
        $status = max_state($status, 2);
        push @parts, "CRIT BATTERY CAPACITY: ${capacity}%";
    } elsif ($capacity < $warn_capacity) {
        $status = max_state($status, 1);
        push @parts, "WARN BATTERY CAPACITY: ${capacity}%";
    } else {
        push @parts, "BATTERY CAPACITY: ${capacity}%";
    }
    push @perf, "'capacity'=${capacity}%;${warn_capacity};${crit_capacity};;";
}

my $load = to_num($result->{$oids{output_load}});
if (defined $load) {
    if ($load > $crit_load) {
        $status = max_state($status, 2);
        push @parts, "CRIT OUTPUT LOAD: ${load}%";
    } elsif ($load > $warn_load) {
        $status = max_state($status, 1);
        push @parts, "WARN OUTPUT LOAD: ${load}%";
    } else {
        push @parts, "OUTPUT LOAD: ${load}%";
    }
    push @perf, "'load'=${load}%;${warn_load};${crit_load};;";
}

my $temp = to_num($result->{$oids{batt_temp}});
if (defined $temp) {
    if ($temp > $crit_temp) {
        $status = max_state($status, 2);
        push @parts, "CRIT BATT TEMP: ${temp}C";
    } elsif ($temp > $warn_temp) {
        $status = max_state($status, 1);
        push @parts, "WARN BATT TEMP: ${temp}C";
    } else {
        push @parts, "BATT TEMP: ${temp}C";
    }
    push @perf, "'temp'=${temp};${warn_temp};${crit_temp};;";
}

my $replace = to_num($result->{$oids{battery_replace}});
if (defined $replace && $replace == 2) {
    $status = max_state($status, 2);
    push @parts, 'BATTERY REPLACEMENT NEEDED';
}

my $out_status = to_num($result->{$oids{output_status}});
if (defined $out_status) {
    my %map = (
        1 => 'UNKNOWN',
        2 => 'ON LINE',
        3 => 'ON BATTERY',
        4 => 'ON SMART BOOST',
        5 => 'TIMED SLEEPING',
        6 => 'SOFTWARE BYPASS',
        7 => 'OFF',
        8 => 'REBOOTING',
        9 => 'SWITCHED BYPASS',
        10 => 'HARDWARE BYPASS',
        11 => 'SLEEPING',
        12 => 'ON SMART TRIM',
    );
    my $label = $map{$out_status} // 'UNKNOWN';
    push @parts, "UPS STATUS: $label";
    if ($out_status == 3 || $out_status == 6 || $out_status == 9 || $out_status == 10) {
        $status = max_state($status, 1);
    }
}

my $remaining = parse_remaining_minutes($result->{$oids{remaining_time}});
if (defined $remaining) {
    push @parts, "MINUTES REMAINING: $remaining";
    push @perf, "'remaining_sec'=" . ($remaining * 60) . "s;;;0;";
}

my %state_text = (0 => 'OK', 1 => 'WARNING', 2 => 'CRITICAL', 3 => 'UNKNOWN');
my $line = join(' - ', @parts);
my $perf = join(' ', @perf);

print $state_text{$status} . " - $line";
print "|$perf" if $perf ne '';
print "\n";
exit $status;

sub create_snmp_session {
    if ($version == 3) {
        return Net::SNMP->session(
            -hostname     => $host,
            -port         => 161,
            -version      => 3,
            -username     => $username,
            -authpassword => $auth_password,
            -authprotocol => lc($auth_protocol),
            -privpassword => $priv_password,
            -privprotocol => lc($priv_protocol),
            -timeout      => 5,
            -retries      => 2,
        );
    }

    return Net::SNMP->session(
        -hostname  => $host,
        -community => $community,
        -port      => 161,
        -version   => $version,
        -timeout   => 5,
        -retries   => 2,
    );
}

sub parse_remaining_minutes {
    my ($raw) = @_;
    return undef if !defined $raw;

    if ($raw =~ /^(\d+)\s+hour/i) {
        my $h = $1;
        my $m = 0;
        if ($raw =~ /\s(\d+):(\d+)/) {
            $m = $1;
        }
        return ($h * 60) + $m;
    }

    if ($raw =~ /^(\d+)\s+minute/i) {
        return $1;
    }

    if ($raw =~ /^(\d+)\s+second/i) {
        return int($1 / 60);
    }

    if ($raw =~ /^\d+$/) {
        return int($raw / 60);
    }

    return undef;
}

sub to_num {
    my ($v) = @_;
    return undef if !defined $v;
    if ($v =~ /(-?\d+(?:\.\d+)?)/) {
        return 0 + $1;
    }
    return undef;
}

sub max_state {
    my ($a, $b) = @_;
    return $a > $b ? $a : $b;
}

sub usage {
    my ($exit_code, $msg) = @_;
    print "$msg\n" if defined $msg;
    print <<'USAGE';
check_ups_apc.pl v2.0.0

Usage:
  check_ups_apc.pl -H <host> [-C <community>] [-v <1|2|3>] [options]

SNMP v1/v2c:
  -H, --host           Hostname or IP
  -C, --community      Community (default: public)
  -v, --version        1 or 2 (default: 2)

SNMP v3:
  -v, --version        3
  -U, --username       Username
  -A, --authpassword   Auth password
  -a, --authprotocol   sha|md5 (default: sha)
  -X, --privpassword   Privacy password
  -x, --privprotocol   aes|des (default: aes)

Threshold options:
  --warn-capacity / --crit-capacity
  --warn-load / --crit-load
  --warn-temp / --crit-temp

  -h, --help           Show this help
USAGE
    exit $exit_code;
}
