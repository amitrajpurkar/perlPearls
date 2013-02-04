# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl au-com-company-scandocs-pgService.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 6;
use au::com::company::scandocs::pgService qw(:all);
BEGIN { use_ok('au::com::company::scandocs::pgService') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.
my $givenShipno = "2020203517";
my $givenDocType = "AQIS Direction";
my ($docid, $branch, $department, $insertAppendFlag, $mgsDesc) = findDocumentInPGServer($givenShipno, $givenDocType);
my $expectedDocid = "3006175";
my $expectedFlag = "UPDATE";
my $expectedMessage = "Successfully completed executing findDocumentInPGServer";
is($docid, $expectedDocid, "testing if valid docid is fetched");
is($insertAppendFlag, $expectedFlag, "testing if insert-append flag is as expected");
is($mgsDesc, $expectedMessage, "testing if success message is as expected");

$givenShipno = "2020300652";
($docid, $branch, $department, $insertAppendFlag, $mgsDesc) = findDocumentInPGServer($givenShipno, $givenDocType);
$expectedDocid = "NODOCID";
$expectedFlag = "INSERT";
is($docid, $expectedDocid, "testing for case when document is not present");
is($insertAppendFlag, $expectedFlag, "testing if insert-append flag is as expected");

