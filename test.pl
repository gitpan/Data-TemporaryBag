# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..10\n"; }
END {print "not ok 1\n" unless $loaded;}
use Data::TemporaryBag;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $t = Data::TemporaryBag->new("ABC");
print "not " if $t->substr(0) ne "ABC";
print "ok 2\n";
$t->add('DEF');
print "not " if $t->substr(1,4) ne "BCDE";
print "ok 3\n";
$t->substr(5,1,'123');
print "not " if $t->value ne "ABCDE123";
print "ok 4\n";
$Data::TemporaryBag::Threshold = 0.02;  # Threshold: 20.48 bytes
$t->add('456789012345');
print "not " if $t->is_saved;
print "ok 5\n";
$t->add('6');
print "not " unless $t->is_saved;
print "ok 6\n";
$t->substr(5,1,'XYZ');
print "not " if $t->value ne "ABCDEXYZ234567890123456";
print "ok 7\n";
$t->substr(5,12,'abc');
print "not " if $t->is_saved;
print "ok 8\n";
print "not " if $t->value ne "ABCDEabc123456";
print "ok 9\n";
$t->add('OPQRSTUVWXYZ');
#sleep 3;
my $fn = $t->is_saved;
eval {
 # Tempfile can't be changed by improper method...
    local *F;
    open(F, ">> $fn") or die; # so, error should occur here or...
    print F "@";
    close F;
    $t->value;                # ... here.
};
print "not " unless $@;
print "ok 10\n";
unlink $fn;

