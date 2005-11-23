# Ensembl module for Bio::EnsEMBL::Variation::Genotype
#
# Copyright (c) 2004 Ensembl
#


=head1 NAME

Bio::EnsEMBL::Variation::Genotype - Abstract base class representing a genotype

=head1 SYNOPSIS

    print $genotype->variation()->name(), "\n";
    print $genotype->allele1(), '/', $genotype->allele2(), "\n";

=head1 DESCRIPTION

This is an abstract base class representing a genotype.  Specific types of
genotype are represented by subclasses such as IndividualGenotype and
PopulationGenotype.  Genotypes are assumed to be for diploid organisms
and are represented by two alleles.

=head1 CONTACT

Post questions to the Ensembl development list: ensembl-dev@ebi.ac.uk

=head1 METHODS

=cut


use strict;
use warnings;

package Bio::EnsEMBL::Variation::Genotype;

use Bio::EnsEMBL::Storable;
use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Utils::Exception qw(throw deprecate warning);

use vars qw(@ISA);

@ISA = qw(Bio::EnsEMBL::Storable);



=head2 allele1

  Arg [1]    : string $newval (optional)
               The new value to set the allele1 attribute to
  Example    : $allele1 = $genotype->allele1()
               $genotype->allele1('A');
  Description: Getter/Setter for one of the two alleles that define this
               genotype.
  Returntype : string
  Exceptions : none
  Caller     : general

=cut

sub allele1 {
  my $self = shift;
  return $self->{'allele1'} = shift if(@_);
  return $self->{'allele1'};
}



=head2 allele2

  Arg [1]    : string $newval (optional)
               The new value to set the allele1 attribute to
  Example    : $allele1 = $genotype->allele2()
               $genotype->allele2('A');
  Description: Getter/Setter for one of the two alleles that define this
               genotype.
  Returntype : string
  Exceptions : none
  Caller     : general

=cut

sub allele2 {
  my $self = shift;
  return $self->{'allele2'} = shift if(@_);
  return $self->{'allele2'};
}

1;
