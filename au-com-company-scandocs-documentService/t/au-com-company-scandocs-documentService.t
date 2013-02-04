# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl au-com-company-scandocs-documentService.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 4;
use au::com::company::scandocs::documentService qw( :all );
BEGIN { use_ok('au::com::company::scandocs::documentService') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $shipno = "2020203517";
my $docid = "999999";
my $tempFile = "./tempFetchedDocument.pdf";
my ($msgCode, $msgDesc) = viewDocumentFromScandocs($docid, $shipno, $tempFile);

is($msgCode, "FAILED", "testing if response is FAILED after fetching for invalid doc-ref-id");
is(( -e $tempFile ), undef, "testing if temp file exists");
like($msgDesc, qr/^url fetch status-code/i,"testing if descriptive message starts with expected phrase");
