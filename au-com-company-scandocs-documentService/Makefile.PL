use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'au::com::company::scandocs::documentService',
    VERSION_FROM      => 'lib/au/com/company/scandocs/documentService.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/au/com/company/scandocs/documentService.pm', # retrieve abstract from module
       AUTHOR         => 'Root <root@syd.company.int.au>') : ()),
);
