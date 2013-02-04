# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl au-com-company-scandocs-ams.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';
use strict;
use warnings;
use Test::More tests => 8;

use au::com::company::scandocs::ams qw( :all );
BEGIN { use_ok('au::com::company::scandocs::ams') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $validDocRefId = "2020203517-3006175";
my $invalidDocRefId = "2020203517-999999";
my $tempFile = "./tempFetchedDocument.pdf";
my ($msgCode, $msgDesc) = fetchFromAms($validDocRefId, $tempFile);
is($msgCode, "OK", "testing if response is OK after fetching for valid doc-ref-id");
isnt(( -e $tempFile ), undef, "testing if temp file exists and is created by fetch operation");
isnt(( -s $tempFile), 0, "testing if temp file has non-zero size");
unlink $tempFile; ## remove the temp file created for above tests

is($tempFile, "./tempFetchedDocument.pdf", "testing if variable value is still intact");
($msgCode, $msgDesc) = fetchFromAms($invalidDocRefId, $tempFile);
is($msgCode, "FAILED", "testing if response is FAILED after fetching for invalid doc-ref-id");
is(( -e $tempFile ), undef, "testing if temp file now exists");
like($msgDesc, qr/^url fetch status-code/i,"testing if descriptive message starts with expected phrase");

#done_testing();
