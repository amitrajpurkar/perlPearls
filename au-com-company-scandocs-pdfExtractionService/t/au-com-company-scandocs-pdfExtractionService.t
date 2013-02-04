# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl au-com-company-scandocs-pdfExtractionService.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 1;
use au::com::company::scandocs::pdfExtractionService;
BEGIN { use_ok('au::com::company::scandocs::pdfExtractionService') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

## ANR::
## trust me, its hard to write unit test case for this module.. it needs an integration test at best .. or may be a mock-test if possible.
## hence leaving this test-case file empty on purpose.
