#
# Ensembl module for Bio::EnsEMBL::Variation::DBSQL::VariationFeatureAdaptor
#
# Copyright (c) 2004 Ensembl
#
# You may distribute this module under the same terms as perl itself
#
#

=head1 NAME

Bio::EnsEMBL::Variation::DBSQL::VariationFeatureAdaptor

=head1 SYNOPSIS

  $vdb = Bio::EnsEMBL::Variation::DBSQL::DBAdaptor->new(...);
  $db  = Bio::EnsEMBL::DBSQL::DBAdaptor->new(...);

  # tell the variation database where core database information can be
  # be found
  $vdb->dnadb($db);

  $va = $vdb->get_VariationAdaptor();
  $vfa = $vdb->get_VariationFeatureAdaptor();
  $sa  = $db->get_SliceAdaptor();

  # Get a VariationFeature by its internal identifier
  $vf = $va->fetch_by_dbID(145);

  # get all VariationFeatures in a region
  $slice = $sa->fetch_by_region('chromosome', 'X', 1e6, 2e6);
  foreach $vf (@{$vfa->fetch_all_by_Slice($slice)}) {
    print $vf->start(), '-', $vf->end(), ' ', $vf->allele_string(), "\n";
  }


  # fetch all genome hits for a particular variation
  $v = $va->fetch_by_name('rs56');

  foreach $vf (@{$vfa->fetch_all_by_Variation($v)}) {
    print $vf->seq_region_name(), $vf->seq_region_start(), '-',
          $vf->seq_region_end(),"\n";
  }

=head1 DESCRIPTION

This adaptor provides database connectivity for VariationFeature objects.
Genomic locations of variations can be obtained from the database using this
adaptor.  See the base class BaseFeatureAdaptor for more information.

=head1 AUTHOR - Graham McVicker

=head1 CONTACT

Post questions to the Ensembl development list ensembl-dev@ebi.ac.uk

=head1 METHODS

=cut

use strict;
use warnings;

package Bio::EnsEMBL::Variation::DBSQL::VariationFeatureAdaptor;

use Bio::EnsEMBL::Variation::VariationFeature;
use Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor;
use Bio::EnsEMBL::Utils::Exception qw(throw);
use Bio::EnsEMBL::Utils::Sequence qw(expand);

our @ISA = ('Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor');

use Data::Dumper;

=head2 fetch_all_by_Variation

  Arg [1]    : Bio::EnsEMBL:Variation::Variation $var
  Example    : my @vfs = @{$vfa->fetch_all_by_Variation($var)};
  Description: Retrieves all variation features for a given variation.  Most
               variations should only hit the genome once and only a return
               a single variation feature.
  Returntype : reference to list Bio::EnsEMBL::Variation::VariationFeature
  Exceptions : throw on bad argument
  Caller     : general

=cut


sub fetch_all_by_Variation {
  my $self = shift;
  my $var  = shift;

  if(!ref($var) || !$var->isa('Bio::EnsEMBL::Variation::Variation')) {
    throw('Bio::EnsEMBL::Variation::Variation arg expected');
  }

  if(!defined($var->dbID())) {
    throw("Variation arg must have defined dbID");
  }

  return $self->generic_fetch("vf.variation_id = ".$var->dbID());
}


sub fetch_all_genotyped_by_Slice{
    my $self = shift;
    my $slice = shift;

    my $constraint = "vf.flags & 1";
    #call the method fetch_all_by_Slice_constraint with the genotyped constraint
    return $self->fetch_all_by_Slice_constraint($slice,$constraint);
}

=head2 fetch_all_by_Slice_Population

   Arg[0]      : Bio::EnsEMBL::Slice $slice
   Arg[1]      : Bio::EnsEMBL::Variation::Population $population
   Example     : my $vf = $vfa->fetch_all_by_Slice_Population($slice,$population);   
   Description : Gets all the VariationFeatures in a certain Slice for a given
                 Population
   ReturnType  : listref of Bio::EnsEMBL::Variation::VariationFeature
   Exceptions  : thrown on bad arguments
   Caller      : general
   
=cut

sub fetch_all_by_Slice_Population{
    my $self = shift;
    my $slice = shift;
    my $population = shift;

    if(!ref($slice) || !$slice->isa('Bio::EnsEMBL::Slice')) {
	throw('Bio::EnsEMBL::Slice arg expected');
    }

    if(!ref($population) || !$population->isa('Bio::EnsEMBL::Variation::Population')) {
	throw('Bio::EnsEMBL::Variation::Population arg expected');
    }
    if(!defined($population->dbID())) {
	throw("Population arg must have defined dbID");
    }
    
    my $constraint = "a.population_id = " . $population->dbID;
    #call the method fetch_all_by_Slice_constraint with the population constraint
    return $self->fetch_all_by_Slice_constraint($slice,$constraint);    
}

# method used by superclass to construct SQL
sub _tables { return (['variation_feature', 'vf'],
		      ['source', 's'],
		      ['variation', 'v'],
		      ['allele','a']); }


sub _default_where_clause {
  my $self = shift;

  return 'v.source_id = s.source_id AND ' . 
         'vf.variation_id = v.variation_id AND ' .
	 'vf.variation_id = a.variation_id';
}

sub _columns {
  return qw( vf.variation_feature_id vf.seq_region_id vf.seq_region_start
             vf.seq_region_end vf.seq_region_strand vf.variation_id
             a.allele v.name vf.map_weight s.name v.validation_status vf.consequence_type);
}



sub _objs_from_sth {
  my ($self, $sth, $mapper, $dest_slice) = @_;
  
  #
  # This code is ugly because an attempt has been made to remove as many
  # function calls as possible for speed purposes.  Thus many caches and
  # a fair bit of gymnastics is used.
  #

  my $sa = $self->db()->dnadb()->get_SliceAdaptor();

  my @features;
  my %slice_hash;
  my %sr_name_hash;
  my %sr_cs_hash;

  my ($variation_feature_id, $seq_region_id, $seq_region_start,
      $seq_region_end, $seq_region_strand, $variation_id,
      $allele, $variation_name, $map_weight, $source_name, $validation_status, $consequence_type );

  $sth->bind_columns(\$variation_feature_id, \$seq_region_id,
                     \$seq_region_start, \$seq_region_end, \$seq_region_strand,
                     \$variation_id, \$allele, \$variation_name,
                     \$map_weight, \$source_name, \$validation_status, \$consequence_type);


  my $asm_cs;
  my $cmp_cs;
  my $asm_cs_vers;
  my $asm_cs_name;
  my $cmp_cs_vers;
  my $cmp_cs_name;
  if($mapper) {
      $asm_cs = $mapper->assembled_CoordSystem();
      $cmp_cs = $mapper->component_CoordSystem();
      $asm_cs_name = $asm_cs->name();
      $asm_cs_vers = $asm_cs->version();
      $cmp_cs_name = $cmp_cs->name();
      $cmp_cs_vers = $cmp_cs->version();
  }
  
  my $dest_slice_start;
  my $dest_slice_end;
  my $dest_slice_strand;
  my $dest_slice_length;
  if($dest_slice) {
      $dest_slice_start  = $dest_slice->start();
      $dest_slice_end    = $dest_slice->end();
      $dest_slice_strand = $dest_slice->strand();
      $dest_slice_length = $dest_slice->length();
  }
  # variables to store the alleles and find out when we have a different variation
  my $cur_variation_feature_id = 0;
  my $variation_feature; #current variation_feature object
  my $alleles = {}; #contains all the alleles for the current variation feature
 FEATURE: while($sth->fetch()) {
     if ($cur_variation_feature_id != $variation_feature_id){	 
	 if ($cur_variation_feature_id != 0){
	     #with a different row, update the alleles in the object and push it
	     $variation_feature->allele_string(join('/',keys %{$alleles}));
	     push @features,$variation_feature;
	     $alleles = {};
	 }
	 #create the object variation_feature

	 #get the slice object
	 my $slice = $slice_hash{"ID:".$seq_region_id};
	 if(!$slice) {
	     $slice = $sa->fetch_by_seq_region_id($seq_region_id);
	     $slice_hash{"ID:".$seq_region_id} = $slice;
	     $sr_name_hash{$seq_region_id} = $slice->seq_region_name();
	     $sr_cs_hash{$seq_region_id} = $slice->coord_system();
	 }
	 #
	 # remap the feature coordinates to another coord system
	 # if a mapper was provided
	     #
	 if($mapper) {
	     my $sr_name = $sr_name_hash{$seq_region_id};
	     my $sr_cs   = $sr_cs_hash{$seq_region_id};
	     
	     ($sr_name,$seq_region_start,$seq_region_end,$seq_region_strand) =
		 $mapper->fastmap($sr_name, $seq_region_start, $seq_region_end,
				  $seq_region_strand, $sr_cs);
	     
	     #skip features that map to gaps or coord system boundaries
	     next FEATURE if(!defined($sr_name));
	     
	     #get a slice in the coord system we just mapped to
	     if($asm_cs == $sr_cs || ($cmp_cs != $sr_cs && $asm_cs->equals($sr_cs))) {
		 $slice = $slice_hash{"NAME:$sr_name:$cmp_cs_name:$cmp_cs_vers"} ||=
		     $sa->fetch_by_region($cmp_cs_name, $sr_name,undef, undef, undef,
					  $cmp_cs_vers);
	     } else {
		 $slice = $slice_hash{"NAME:$sr_name:$asm_cs_name:$asm_cs_vers"} ||=
		     $sa->fetch_by_region($asm_cs_name, $sr_name, undef, undef, undef,
					  $asm_cs_vers);
	     }
	 }
	 
	 #
	 # If a destination slice was provided convert the coords
	 # If the dest_slice starts at 1 and is foward strand, nothing needs doing
	 #
	 if($dest_slice) {
	     if($dest_slice_start != 1 || $dest_slice_strand != 1) {
		 if($dest_slice_strand == 1) {
		     $seq_region_start = $seq_region_start - $dest_slice_start + 1;
		     $seq_region_end   = $seq_region_end   - $dest_slice_start + 1;
		 } else {
		     my $tmp_seq_region_start = $seq_region_start;
		     $seq_region_start = $dest_slice_end - $seq_region_end + 1;
		     $seq_region_end   = $dest_slice_end - $tmp_seq_region_start + 1;
		     $seq_region_strand *= -1;
		 }
		 
		 #throw away features off the end of the requested slice
		 if($seq_region_end < 1 || $seq_region_start > $dest_slice_length) {
		     next FEATURE;
		 }
	     }
	     $slice = $dest_slice;
	 }
	 
	 
	 $validation_status = 0 if (!defined $validation_status);
	 my @states = split(',',$validation_status);
	 $variation_feature = Bio::EnsEMBL::Variation::VariationFeature->new_fast({'start'    => $seq_region_start,
										   'end'      => $seq_region_end,
										   'strand'   => $seq_region_strand,
										   'slice'    => $slice,
										   'variation_name' => $variation_name,
										   'adaptor'  => $self,
										   'dbID'     => $variation_feature_id,
										   'map_weight' => $map_weight,
										   'source'   => $source_name,
										   'validation_code' => \@states,
										   'consequence_type' => $consequence_type || 'INTERGENIC',
										   '_variation_id' => $variation_id});
	 
	     
	     
     }
     #update the alleles
     $alleles->{$allele}++;
     $cur_variation_feature_id = $variation_feature_id;     
 }    
  #update last variation_feature
  if (defined($variation_feature)){
      $variation_feature->allele_string(join('/',keys %{$alleles}));
      push @features,$variation_feature;
  }
  
  return \@features;
}





=head2 list_dbIDs

  Arg [1]    : none
  Example    : @feature_ids = @{$simple_feature_adaptor->list_dbIDs()};
  Description: Gets an array of internal ids for all simple features in 
               the current db
  Returntype : list of ints
  Exceptions : none
  Caller     : ?

=cut

sub list_dbIDs {
  my $self = shift;
  return $self->_list_dbIDs('variation_feature');
}



1;
