#!/usr/bin/env perl
use strict;
use warnings;
use autodie qw( chdir close open );
use experimental qw( signatures switch );

use File::Path qw( remove_tree );
use File::Slurp qw( read_file );
use File::Temp qw( tempdir );
use FindBin;
use Guard;
use HTTP::Request;
use HTTP::Request::Common;
use JSON::XS qw( decode_json );
use LWP::UserAgent;
use Test::More;
use YAML::Tiny qw( LoadFile );

# do we have all info needed for running a test?
my $lang = shift @ARGV
  or die "Must indicate the language you want to test\n";
die "Invalid language '$lang'\n"
  if not -d "lang/$lang";
my $spec_file = shift @ARGV
  or die "Must indicate a YAML test file\n";
my $specs       = LoadFile($spec_file);
my ($test_name) = $spec_file =~ m{ ([^/]+) [.] .* $}x;
my $code        = read_file( glob "lang/$lang/t/$test_name.*" );
my $test_count  = 0;

# resource limitation tests only run remotely
if ( $test_name eq 'hog' && is_running_tests_locally() ) {
    plan skip_all => 'Resource hogging tests only run remotely';
    exit;
}

# create a script for running this code
my $create_response = create_script( $lang, $code );
my $script_id = $create_response->{script};
if ( not $script_id ) {
    $test_count++;
    diag( $create_response->{error_message} );
    if ( ref($specs) eq 'HASH' ) {
        matches(
            $create_response->{error_message},
            $specs->{creation}{error_message},
            'compiler error message'
        );
    }
    else {
        fail('create script');
    }
    done_testing($test_count);
    exit;
}
else {
    $test_count++;
    pass("create script $script_id");
}

# make HTTP requests against our new script
for my $spec (@$specs) {
    $test_count += 2;    # we'll run at least this many tests

    # which test are we running?
    $spec = normalize_test_spec($spec);
    my $name = $spec->{name};

    # do response details match?
    my $res = execute_spec($spec);
    is( $res->code, $spec->{response_status_code}, "status code - $name" );
    matches(
        $res->decoded_content,
        $spec->{response_content},
        "content - $name"
    );

    # do response headers match?
    my $headers = $spec->{response_headers};
    $test_count += scalar keys %$headers;
    while ( my ( $k, $v ) = each %$headers ) {
        is( $res->headers->header($k), $v, "header $k - $name" );
    }
}

$test_count++;
ok( delete_script($script_id), "delete script" );

done_testing($test_count);
exit;

sub env($name) {
    return $ENV{ 'HOOKSCRIPT_' . uc($name) };
}

sub is_running_tests_locally {
    return not env('api_token');
}

sub post($path, $params) {
    my $res      = agent()->post( path_to_url($path), $params );
    my $content  = $res->decoded_content;
    my $response = decode_json $content;
    $response->{status} = $res->code;

    return $response;
}

sub http_delete($path) {
    my $res     = agent()->delete( path_to_url($path) );
    my $content = $res->decoded_content;
    if ( $res->is_error ) {
        die $res->status_line, "\n", $content, "\n";
    }

    return decode_json($content);
}

sub path_to_url($path) {
    my $token = env('api_token');
    if ( my $v = env('version') ) {
        return "https://$v-dot-hook-tastic.appspot.com/api/$path?t=$token";
    }
    return "https://www.hookscript.com/api/$path?t=$token";
}

sub agent {
    return LWP::UserAgent->new( timeout => 20 );
}

sub normalize_test_spec($raw) {
    my $spec = {};
    $spec->{post_params} = $raw->{post_params};

    # desugar HTTP request description
    if ( my $req = $raw->{request} ) {
        if ( ref $req ) {
            $spec->{name}            = $req->{method} . ' ' . $req->{path};
            $spec->{method}          = $req->{method};
            $spec->{path}            = $req->{path};
        }
        else {
            my ( $method, $path ) = $req =~ m{ ^ ([A-Z]+) \s+ (.*) $ }x;
            $spec->{name}   = $req;
            $spec->{method} = $method;
            $spec->{path}   = $path;
        }
    }

    # desugar HTTP response description
    if ( my $res = $raw->{response} ) {
        if ( not ref $res ) {
            $res = { content => $res };
        }

        $spec->{response_status_code} = $res->{status} // 200;
        $spec->{response_headers}{content_type} = $res->{headers}{content_type}
          // 'text/plain';
        $spec->{response_content} = $res->{content};
    }

    return $spec;
}

sub execute_spec($spec) {
    my $method = $spec->{method};
    my $v      = env('version');
    my $base =
      $v ? "https://$v-dot-hook-tastic.appspot.com" : "https://www.runhook.com";
    ( my $url = $spec->{path} ) =~ s#^/#$base/$script_id#;
    my $req;
    given ($method) {
        when ('POST') {
            my $params = $spec->{post_params} // {};
            $req = HTTP::Request::Common::POST( $url, $params );
        }
        default {
            $req = HTTP::Request->new( $method, $url );
        }
    }

    if ( is_running_tests_locally() ) {
        scope_guard {
            unlink 'log', 'request', 'response';
        };

        # generate HTTP request
        chdir $script_id;
        $req->protocol('HTTP/1.1') if not $req->protocol;
        open my $fh, '>', 'request';
        print $fh $req->as_string;
        close $fh;

        my $rc = system "$FindBin::Bin/../lang/$lang/run";
        if ($rc) {
            my $code = $rc >> 8;
            my $msg  = "Script exited with code $code";
            my $res  = HTTP::Response->new( 503, $msg );
            $res->header( content_type => 'text/plain' );
            my $log = read_file 'log';
            $res->content("$msg\n$log");
            return $res;
        }

        # parse HTTP response
        my $text = read_file 'response';
        my $res  = HTTP::Response->parse($text);
        return $res;
    }

    return agent()->request($req);
}

sub create_script($lang, $code) {
    if ( is_running_tests_locally() ) {
        scope_guard {
            unlink 'log', 'source';
        };

        my $dir = tempdir( 'hookscript-XXXX', TMPDIR => 1 );
        chdir $dir;
        open my $fh, '>', 'source';
        print $fh $code;
        close $fh;

        if ( system "$FindBin::Bin/../lang/$lang/compile" ) {
            my $errors = read_file 'log';
            my $code = 'Script exited with code ' . ( $? >> 8 );
            return { error_message => "$code\n$errors" };
        }

        return { script => $dir };
    }

    my $res = post(
        'script',
        {
            lang => $lang,
            code => $code,
        }
    );
    return $res;
}

sub delete_script($script_id) {
    if ( is_running_tests_locally() ) {
        chdir "/";
        remove_tree $script_id;
        return 1;
    }

    my $res = http_delete("script/$script_id");
    return $res->{script};
}

sub matches($got, $expected, $test_name) {
    given ($expected) {
        when (m#^/(.*)/$#) {
            like( $got, qr/$1/s, $test_name );
        }
        default {
            is( $got, $expected, $test_name );
        }
    }
}
