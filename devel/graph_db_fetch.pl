use warnings;
use strict;

use DBI;
use Data::Dumper;

my $driver   = "SQLite";
my $database = "db/envui.db";
my $dsn = "DBI:$driver:dbname=$database";
my $dbh = DBI->connect($dsn, '', '', { RaiseError => 1 })
    or die $DBI::errstr;

# get in descending order

my $sth = $dbh->prepare(
    "select * from (
        select * from stats order by id DESC limit 100
    ) sub
        order by id asc;"
);

$sth->execute;
my $aref = $sth->fetchall_arrayref;

# perl -E '@a=qw(15 16); $c=10-@a; for (0..$c){push @a, 0};@b; @a=reverse @a; push @b, [$_, $a[$_]] for 0..$#a; say "$_->[0], $_->[1]" for @b'

my $check = 1;
my $count = 0;
my %data;

for (@$aref){
    # every 4 entries; typically we have 4 polls per minute
    if ($check % 4 == 1){
        push @{ $data{temp} }, [$count, $_->[2]];
        push @{ $data{humidity} }, [$count, $_->[3]];
        $count++;
    }
    $check++;
}

print Dumper \%data;
