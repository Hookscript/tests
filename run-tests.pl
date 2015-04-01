#!/usr/bin/env perl
use strict;
use warnings;
use experimental qw( signatures switch );
use autodie qw( system );

use FindBin;
use TAP::Formatter::HTML;
use TAP::Harness;

# which languages and tests are wanted?
my @langs;
my @test_files;
my $bad_argument;
for (@ARGV) {
    when ( -d "lang/$_" ) {
        push @langs, $_;
    }
    when (-f) {
        push @test_files, $_;
    }
    default {
        $bad_argument = 1;
        warn "Unexpected argument: $_\n";
    }
}
die "Fix argument errors and run again\n" if $bad_argument;
if ( not @langs ) {
    @langs = map { s'^lang/''; $_ } glob "lang/*";
}
if ( not @test_files ) {
    @test_files = glob "t/*.yaml";
}

# run each test for each language
my @tests;
for my $yaml_file (@test_files) {
    for my $lang (@langs) {
        my ($name) = $yaml_file =~ m{ / ([^.]+) }x;
        push @tests, [ "$yaml_file.$lang", "$lang $name" ];
    }
}

# have TAP run the tests
my $formatter = TAP::Formatter::HTML->new(
    {
        output_file => 'tap.html',
        verbosity   => -3,           # normal verbosity
        stdout      => undef,
    }
);
my $harness = TAP::Harness->new(
    {
        merge => 'yes',
        jobs  => $ENV{HOOKSCRIPT_API_TOKEN} ? 2 : 8,

        formatter => $formatter,

        exec => sub($harness,$test_file) {
            given ($test_file) {
                when (m{ / ([^.]+) [.]yaml [.](.+) $ }x) {
                    my ( $name, $lang ) = ( $1, $2 );
                    return [
                        "$FindBin::Bin/run-a-test.pl", $lang,
                        "t/$name.yaml"
                    ];
                }
            }
        },
    }
);
$harness->runtests(@tests);

system "open tap.html";
