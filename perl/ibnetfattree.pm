# Copyright (c) 2015, Lawrence Livermore National Security, LLC.
# Produced at the Lawrence Livermore National Laboratory.
# Written by Adam Moody <moody20@llnl.gov>.
# LLNL-CODE-667975.
# All rights reserved.
# This file is part of the IBTopo packag.
# For details, see https://github.com/hpc/ibtopo
# Please also read the LICENSE file.

package ibnetfattree;
use strict;
use vars qw(@ISA);
use ibnetupdown;

# This package determines the switch level structure of an Infiniband
# network using the ibnetdiscover output and exposes this information
# via an API.  The structure is assumed to be a fat-tree.
#
# Author: Adam Moody <moody20@llnl.gov>

@ISA = qw(ibnetupdown);

# create a new object
#  $fattree = new $ibnetfattree($ibnetdiscover_file)
sub new
{
  my $type = shift;
  my $file = shift;
  my ($self) = ibnetupdown->new($file);
  $self->{fattree} = {};
  parse_fattree($self);
  return bless $self, $type;
}

# for a given level, return the number of leaves at that level
#  $num_leaves = $fattree->num_leaves_at_level($level_number)
sub num_leaves_at_level
{
  my $self  = shift;
  my $level = shift;
  return scalar(keys %{$self->{fattree}{leaves}{level}{$level}{leaf}});
}

# for a given level, list the leaf ids at that level
#  @list_leaves = $fattree->list_leaves_at_level($level_number)
sub list_leaves_at_level
{
  my $self  = shift;
  my $level = shift;
  return (sort {$a <=> $b} keys %{$self->{fattree}{leaves}{level}{$level}{leaf}});
}

# for a given switch guid, list the leaf ids for its children
#  @list_leaves = $fattree->list_child_leaves_for_guid($switch_guid)
sub list_child_leaves_for_guid
{
  my $self  = shift;
  my $guid = shift;
  return (sort {$a <=> $b} keys %{$self->{fattree}{leaves}{guid}{$guid}{childleaves}});
}

# for a given switch guid and child leaf id, list the ports
# leading to that leaf
#  @list_ports = $fattree->list_ports_to_child_leaf_for_guid($switch_guid, $leaf_id)
sub list_ports_to_child_leaf_for_guid
{
  my $self  = shift;
  my $guid = shift;
  my $leaf = shift;
  return (sort {$a <=> $b} @{$self->{fattree}{leaves}{guid}{$guid}{childleaves}{$leaf}{ports}});
}

# for a given node guid, return what leaf id it is part of
# at a given level
#  $leaf_id = $fattree->leaf($node_guid, $level_number)
sub leaf_at_level
{
  my $self  = shift;
  my $guid  = shift;
  my $level = shift;

  my $leaf_id = undef;
  if (defined $self->{fattree}{guid2leaf}{$guid}{$level}) {
    $leaf_id = $self->{fattree}{guid2leaf}{$guid}{$level};
  }
  return $leaf_id;
}

###########
# PRIVATE FUNCTIONS
###########

# This uses $self, which is already an ibnetupdown object,
# to extract the fattree network structure
sub parse_fattree
{
  my $self = shift;
  my $s = \%{$self->{fattree}};

  #-------------
  # Determine leaf structures
  #-------------

  $$s{leaves} = ();
  $$s{guid2leaf} = ();

  my $num_levels = $self->num_levels();

  # assign leaf ids to the leaf-level switches
  if ($num_levels >= 1) {
    my $lev = 1;
    my $num_leaves = 0;
    foreach my $guid (sort {$a cmp $b} $self->list_guids_at_level($lev)) {
      my $leaf = $num_leaves;
#print "processing leaf switch $guid... assigned to $leaf\n";
      $$s{guid2leaf}{$guid}{$lev} = $leaf;
      $$s{leaves}{level}{$lev}{leaf}{$leaf}{parent_guids}{$guid} = 1;

      # assign each node to this leaf
      foreach my $port ($self->list_down_ports($guid)) {
        my ($destguid, $destport) = $self->end_point($guid, $port);
        $$s{guid2leaf}{$destguid}{$lev} = $leaf;
        $$s{leaves}{level}{$lev}{leaf}{$leaf}{node_guids}{$destguid} = 1;
      }

      $num_leaves++;
    }
  }

  # identify 1st-level and 2nd-level leaves
  # parents and children in each leaf,
  # as well as the number of ports to each child
  for(my $lev = 2; $lev < $num_levels; $lev++) {
    my $num_leaves = 0;
    foreach my $guid (sort {$a cmp $b} $self->list_guids_at_level($lev)) {
#print "processing $guid at level $lev...";
      # determine my set of immediate children (guids on downlinks)
      # and the set of leaf ids they belong to
      my %children = ();
      foreach my $port (sort {$a <=> $b} $self->list_down_ports($guid)) {
        # get child guid and port
        my ($destguid, $destport) = $self->end_point($guid, $port);

        # record the guid of each child and the port to reach each him
        $children{guid}{$destguid}{port} = $port;

        # record the leaf id of each child for the level below
        # at the highest level, there may be more than one connection
        # to the same leaf id
        my $leaf = $$s{guid2leaf}{$destguid}{$lev-1};
        $children{leaf}{$leaf}++;
      }

      my $leaf = undef;

      # for each leaf id of our children, check whether that leaf has
      # already been assigned to a leaf in this level
      foreach my $childleaf (keys %{$children{leaf}}) {
        if (defined $$s{leaves}{level}{$lev}{child2leaf}{$childleaf}) {
          $leaf = $$s{leaves}{level}{$lev}{child2leaf}{$childleaf};
          last;
        }
      }

      # if we found a leaf for this level,
      # check that all children have the same leaf id
      if (defined $leaf) {
        # check whether all children which are assigned to a
        # leaf are consistent
        my $consistent = 1;
        foreach my $childleaf (keys %{$children{leaf}}) {
           if (defined $$s{leaves}{level}{$lev}{child2leaf}{$childleaf}) {
             if ($leaf != $$s{leaves}{level}{$lev}{child2leaf}{$childleaf}) {
               $consistent = 0;
             }
           }
        }

        foreach my $childleaf (keys %{$children{leaf}}) {
          if (not defined $$s{leaves}{level}{$lev}{child2leaf}{$childleaf}) {
            # at least one child is assigned to a leaf, but not all, if those that
            # are assigned to the same one, assign the rest to the same one
            print "ibnetfattree.pm: ERROR: some child is defined to a leaf, but not all\n";
            if ($consistent) {
              foreach my $childleaf (keys %{$children{leaf}}) {
                $$s{leaves}{level}{$lev}{child2leaf}{$childleaf} = $leaf;
              }
            } else {
              print "ibnetfattree.pm: ERROR: children assigned to different leaves\n";
              exit 1;
            }
          }
          if ($leaf != $$s{leaves}{level}{$lev}{child2leaf}{$childleaf}) {
            my $old_leaf = $$s{leaves}{level}{$lev}{child2leaf}{$childleaf};
            my @parent_guids = (keys %{$$s{leaves}{level}{$lev-1}{leaf}{$childleaf}{parent_guids}});
            print "ibnetfattree.pm: ERROR: child belongs to a different leaf $leaf vs $old_leaf, parent $guid, old parents: ", join(" ", @parent_guids), "\n";
            my @node1_guids = (sort {$a cmp $b} keys %{$$s{leaves}{level}{$lev-1}{leaf}{$leaf}{node_guids}});
            my @node2_guids = (sort {$a cmp $b} keys %{$$s{leaves}{level}{$lev-1}{leaf}{$childleaf}{node_guids}});
            my @node1_names = ();
            foreach my $node_guid (@node1_guids) {
              my $node_name = $self->name($node_guid);
              push @node1_names, $node_name;
            }
            my @node2_names = ();
            foreach my $node_guid (@node2_guids) {
              my $node_name = $self->name($node_guid);
              push @node2_names, $node_name;
            }
            print "node guids 1: ", join(" ", @node1_names), "\n";
            print "node guids 2: ", join(" ", @node2_names), "\n";

            foreach my $port (sort {$a <=> $b} $self->list_down_ports($guid)) {
              # get child guid and port
              my ($destguid, $destport) = $self->end_point($guid, $port);
              my $leaf = $$s{guid2leaf}{$destguid}{$lev};
              print "$guid:$port --> $destguid:$destport (leaf $leaf)\n";
            }

            exit 1;
          }
        }
      }

      # if we didn't find a leaf, define a new one
      if (not defined $leaf) {
        # take the next available leaf id
        $leaf = $num_leaves;
        $num_leaves++;

        # remember the leafid for each child in this level
        foreach my $childguid (keys %{$children{guid}}) {
          my $childleaf = $$s{guid2leaf}{$childguid}{$lev-1};
          $$s{leaves}{level}{$lev}{leaf}{$leaf}{child_leaf}{$childleaf}++;
          $$s{leaves}{level}{$lev}{child2leaf}{$childleaf} = $leaf;

          $$s{leaves}{level}{$lev}{leaf}{$leaf}{child_guids}{$childguid}++;
          $$s{guid2leaf}{$childguid}{$lev} = $leaf;

          # record the set of node guids the child leaf contains
          # and record to which leaf each node belongs
          foreach my $node (keys %{$$s{leaves}{level}{$lev-1}{leaf}{$childleaf}{node_guids}}) {
            $$s{leaves}{level}{$lev}{leaf}{$leaf}{node_guids}{$node} = 1;
            $$s{guid2leaf}{$node}{$lev} = $leaf;
          }
        }
      }

      # record the set of ports from this guid to reach this child leaf
      foreach my $childguid (keys %{$children{guid}}) {
        my $childleaf = $$s{guid2leaf}{$childguid}{$lev-1};
        my $port = $children{guid}{$childguid}{port};
        push @{$$s{leaves}{guid}{$guid}{childleaves}{$childleaf}{ports}}, $port;
      }

      # join the leaf
#print "assigned to $leaf\n";
      $$s{guid2leaf}{$guid}{$lev} = $leaf;
      $$s{leaves}{level}{$lev}{leaf}{$leaf}{parent_guids}{$guid} = 1;
    }
  }
}

1;
