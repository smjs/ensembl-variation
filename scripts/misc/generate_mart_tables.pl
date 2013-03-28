#!/usr/bin/env perl

=head1 LICENSE

  Copyright (c) 1999-2013 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

    http://www.ensembl.org/info/about/legal/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk.org>.

=cut

use DBI;
use Getopt::Long;

my $config = {};

GetOptions(
    $config,
    'host|h=s',
    'user|u=s',
    'port|p=s',
    'database|db=s',
    'password|p=s',
) or die "ERROR: Could not parse command line options\n";

# check options
# perl generate_mart_tables --host ensexa-03 --user ensadmin --port 3306 --database at7_pig_71_sift -password
for (qw(host user port database password)) {
    die ("ERROR: $_ not defined, use --$_\n") unless defined $config->{$_};
}
my $dbc = DBI->connect(sprintf("DBI:mysql(RaiseError=>1):host=%s;port=%s;db=%s",
                        $config->{host},
                        $config->{port},
                        $config->{database}), $config->{user}, $config->{password});

my $tables;
my $sth = $dbc->prepare(qq{SHOW TABLES LIKE 'MTMP_%'});
$sth->execute();
$sth->bind_columns(\$table);
$tables->{$table} = 1 while $sth->fetch;
$sth->finish;
$sth = $dbc->prepare(qq{SHOW TABLES LIKE '%subsnp_map%'});
$sth->execute();
$sth->bind_columns(\$table);
$tables->{$table} = 1 while $sth->fetch;
$sth->finish;

my $mtmp_tables = get_mtmp_tables();
foreach my $mtmp_table (keys %$mtmp_tables) {
    if ($tables->{$mtmp_table}) {
        $dbc->do(qq{TRUNCATE $mtmp_table;});
    } else {
        print $mtmp_tables->{$mtmp_table}->{'create'}, "\n";
        $dbc->do($mtmp_tables->{$mtmp_table}->{'create'});
    }
    print $mtmp_tables->{$mtmp_table}->{'insert'}, "\n";
    $dbc->do($mtmp_tables->{$mtmp_table}->{'insert'});
    if ($mtmp_tables->{$mtmp_table}->{'index'}) {
        $dbc->do($mtmp_tables->{$mtmp_table}->{'index'});
    }
}

sub get_mtmp_tables {
    return {
    'MTMP_allele' => {
        'create' => qq{
            CREATE TABLE `MTMP_allele` (
            `allele_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
            `variation_id` int(10) unsigned NOT NULL,
            `subsnp_id` int(15) unsigned DEFAULT NULL,
            `allele` varchar(25000) DEFAULT NULL,
            `frequency` float DEFAULT NULL,
            `sample_id` int(10) unsigned DEFAULT NULL,
            `count` int(10) unsigned DEFAULT NULL,
            PRIMARY KEY (`allele_id`),
            KEY `subsnp_idx` (`subsnp_id`),
            KEY `variation_idx` (`variation_id`,`allele`(10))
            ) ENGINE=MyISAM DEFAULT CHARSET=latin1; },
        'insert' => qq{
            INSERT INTO MTMP_allele
            SELECT a.allele_id, a.variation_id, a.subsnp_id, ac.allele, a.frequency, a.sample_id, a.count
            FROM allele a, allele_code ac
            WHERE a.allele_code_id = ac.allele_code_id; },
        'index' => '',
    },
    'MTMP_population_genotype' => {
        'create' => qq{
            CREATE TABLE `MTMP_population_genotype` (
            `population_genotype_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
            `variation_id` int(10) unsigned NOT NULL,
            `subsnp_id` int(15) unsigned DEFAULT NULL,
            `allele_1` varchar(25000) DEFAULT NULL,
            `allele_2` varchar(25000) DEFAULT NULL,
            `frequency` float DEFAULT NULL,
            `sample_id` int(10) unsigned DEFAULT NULL,
            `count` int(10) unsigned DEFAULT NULL,
            PRIMARY KEY (`population_genotype_id`),
            UNIQUE KEY `pop_genotype_idx` (`variation_id`,`subsnp_id`,`frequency`,`sample_id`,`allele_1`(5),`allele_2`(5)),
            KEY `variation_idx` (`variation_id`),
            KEY `subsnp_idx` (`subsnp_id`),
            KEY `sample_idx` (`sample_id`)
            ) ENGINE=MyISAM DEFAULT CHARSET=latin1; },
        'insert' => qq{
            INSERT INTO MTMP_population_genotype
            SELECT p.population_genotype_id, p.variation_id, p.subsnp_id, ac1.allele, ac2.allele, p.frequency, p.sample_id, p.count
            FROM population_genotype p, genotype_code gc1, genotype_code gc2, allele_code ac1, allele_code ac2
            WHERE p.genotype_code_id = gc1.genotype_code_id AND gc1.haplotype_id = 1 AND gc1.allele_code_id = ac1.allele_code_id
AND p.genotype_code_id = gc2.genotype_code_id AND gc2.haplotype_id = 2 AND gc2.allele_code_id = ac2.allele_code_id; },
        'index' => '', 
    },
    'subsnp_map' => {
        'create' => qq{
            CREATE TABLE `subsnp_map` (
            `variation_id` int(11) unsigned NOT NULL,
            `subsnp_id` int(11) unsigned DEFAULT NULL
            ) ENGINE=MyISAM DEFAULT CHARSET=latin1; },
        'insert' => qq{
            INSERT INTO subsnp_map (variation_id, subsnp_id)
            SELECT variation_id, subsnp_id
            FROM variation_synonym; },
        'index' => qq{CREATE INDEX variation_idx on subsnp_map (variation_id);},
    }};
}
1;
