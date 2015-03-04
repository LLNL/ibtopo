# Copyright (c) 2015, Lawrence Livermore National Security, LLC.
# Produced at the Lawrence Livermore National Laboratory.
# Written by Adam Moody <moody20@llnl.gov>.
# LLNL-CODE-667975.
# All rights reserved.
# This file is part of the IBTopo packag.
# For details, see https://github.com/hpc/ibtopo
# Please also read the LICENSE file.

package ibnetupdown;
use strict;
use vars qw(@ISA);
use ibnetdiscover;

# This package determines the switch level structure of an Infiniband
# network using the ibnetdiscover output and exposes this information
# via an API.  The structure is assumed to be a fat tree.
#
# Author: Adam Moody <moody20@llnl.gov>

@ISA = qw(ibnetdiscover);

# create a new object
#  $updown = new $ibnetupdown($ibnetdiscover_file)
sub new
{
  my $type = shift;
  my $file = shift;
  my ($self) = ibnetdiscover->new($file);
  $self->{updown} = {};
  parse_updown($self);
  return bless $self, $type;
}

# return the number of levels in the network 0 to N-1 with 0 being
# the bottom (hca) level
#  $num_levels = $updown->num_levels()
sub num_levels
{
  my $self = shift;
  return scalar(keys %{$self->{updown}{levels}});
}

# for a given level, list the guids of items at that level
#  @list_guids = $updown->list_guids_at_level($level_number)
sub list_guids_at_level
{
  my $self  = shift;
  my $level = shift;
  if (defined $self->{updown}{levels}{$level}) {
    return (keys %{$self->{updown}{levels}{$level}{guids}});
  }
  return undef;
}

# for a given guid, return what level it is in the network
#  $level_number = $updown->level($guid)
sub level
{
  my $self = shift;
  my $guid = shift;
  if (defined $self->{updown}{guids}{$guid} and defined $self->{updown}{guids}{$guid}{level}) {
    return $self->{updown}{guids}{$guid}{level};
  }
  return undef;
}

# given a guid, list its up ports
#  @list_up_ports = $updown->list_up_ports($guid)
sub list_up_ports
{
  my $self = shift;
  my $guid = shift;
  if (defined $self->{updown}{guids}{$guid} and defined $self->{updown}{guids}{$guid}{up_ports}) {
    return (sort {$a <=> $b} keys %{$self->{updown}{guids}{$guid}{up_ports}});
  }
  return undef;
}

# given a guid, list its down ports
#  @list_down_ports = $updown->list_down_ports($guid)
sub list_down_ports
{
  my $self = shift;
  my $guid = shift;
  if (defined $self->{updown}{guids}{$guid} and defined $self->{updown}{guids}{$guid}{down_ports}) {
    return (sort {$a <=> $b} keys %{$self->{updown}{guids}{$guid}{down_ports}});
  }
  return undef;
}

# given src and dest guids, return the number of ports available to
# reach dest from src with minimal hops
#  $num_ports_to = $updown->num_ports_to($src_guid, $dest_guid)
sub num_ports_to
{
  my $self = shift;
  my $src  = shift;
  my $dst  = shift;
  if (defined $self->{updown}{guids}{$src}{via_minhop}{$dst}) {
    return scalar(keys %{$self->{updown}{guids}{$src}{via_minhop}{$dst}{ports}});
  }
  return 0;
}

# given src and dest guids, list ports from src that lead to dest
# with minimal hops
#  @list_ports_to = $updown->list_ports_to($src_guid, $dest_guid)
sub list_ports_to
{
  my $self = shift;
  my $src  = shift;
  my $dst  = shift;
  if (defined $self->{updown}{guids}{$src}{via_minhop}{$dst}) {
    return (sort {$a <=> $b} keys %{$self->{updown}{guids}{$src}{via_minhop}{$dst}{ports}});
  }
  return 0;
}

# given src and dest guids, return the number of down ports available
# to reach dest from src with minimal hops
#  $num_down_ports_to = $updown->num_down_ports_to($src_guid, $dest_guid)
sub num_down_ports_to
{
  my $self = shift;
  my $src  = shift;
  my $dst  = shift;
  if (defined $self->{updown}{guids}{$src}{via_down}{$dst}) {
    return scalar(keys %{$self->{updown}{guids}{$src}{via_down}{$dst}{ports}});
  }
  return 0;
}

# given src and dest guids, list down ports from src that lead to dest
# with minimal hops
#  @list_down_ports_to = $updown->list_down_ports_to($src_guid, $dest_guid)
sub list_down_ports_to
{
  my $self = shift;
  my $src  = shift;
  my $dst  = shift;
  if (defined $self->{updown}{guids}{$src}{via_down}{$dst}) {
    return (keys %{$self->{updown}{guids}{$src}{via_down}{$dst}{ports}});
  }
  return 0;
}

###########
# PRIVATE FUNCTIONS
###########

# This uses $self, which is already an ibnetdiscover object,
# to extract the up*/down* network structure
sub parse_updown
{
  my $self = shift;

  #-------------
  # Determine network levels
  #-------------

  # first, set all nodes (hcas) to level 0
  foreach my $guid ($self->list_hcas()) {
    $self->{updown}{guids}{$guid}{level} = 0;
    $self->{updown}{levels}{0}{guids}{$guid} = 1;
  }

  # TODO: i think there is an infinite loop here if there is a switch
  # which are not attached to any nodes, if that condition is possible

  # then, set all other objects (switches) to be some level determined
  # by their hop distance from the nodes
  while (1) {
    my $nothing_changed = 1;
    for my $guid ($self->list_guids()) {
      # get current level for this guid
      my $min_level = undef;
      if (defined $self->{updown}{guids}{$guid}{level}) {
        $min_level = $self->{updown}{guids}{$guid}{level};
      }

      # check all ports to see whether there is a smaller level
      # defined on the other end
      my $update_level = 0;
      foreach my $port ($self->list_connected_ports($guid)) {
        my ($destguid, $destport) = $self->end_point($guid, $port);
        if (defined $self->{updown}{guids}{$destguid}{level}) {
          my $lev = $self->{updown}{guids}{$destguid}{level} + 1;
          if (not defined $min_level or $lev < $min_level) {
            $min_level = $lev;
            $update_level = 1;
          }
        }
      }

      # if we found a new level for this guid, record it
      if ($update_level) {
        # identified a level for this guid, record it
        $self->{updown}{guids}{$guid}{level} = $min_level;
        $nothing_changed = 0;
      }
    }
    if ($nothing_changed) {
      last;
    }
  }

  # now we've settled on a minimum level for all guids, go back
  # through and set the global level lists
  for my $guid ($self->list_guids()) {
    my $min_level = $self->{updown}{guids}{$guid}{level};
    $self->{updown}{levels}{$min_level}{guids}{$guid} = 1;
  }

  #-------------
  # Determine link directions and items reachable via minhop and
  # pure down-links
  #-------------

  # all levels are defined, now determine which nodes and switches
  # can be reached nodes will route up*/down*, while switches use
  # min-hop

  # first, count the number of levels in the network
  my $num_levels = scalar(keys %{$self->{updown}{levels}});

  # for level 0 guids (the nodes), each node can only reach itself,
  # and it should have no downlinks
  foreach my $guid (keys %{$self->{updown}{levels}{0}{guids}}) {
    my $g = \%{$self->{updown}{guids}{$guid}};
    $$g{distance}{$guid} = 0;             # the node can reach itself with a hop distance of 0
    $$g{via_minhop}{$guid}{ports}{0} = 1; # special port 0 to send to myself
    $$g{via_down}{$guid}{ports}{0}   = 1; # special port 0 to send to myself
    foreach my $port ($self->list_connected_ports($guid)) {
      my ($destguid, $destport) = $self->end_point($guid, $port);
      my $dest_g = \%{$self->{updown}{guids}{$destguid}};
      if (defined $$dest_g{level}) {
          if ($$dest_g{level} < $$g{level}) {
            # a downlink from a node shouldn't happen
            $$g{down_ports}{$port} = 1;
            print "ibnetupdown.pm: ERROR: Level-0 node found to have a downlink!!\n";
            exit 1;
          } elsif ($$dest_g{level} > $$g{level}) {
            # an uplink from a node is typical
            $$g{up_ports}{$port} = 1;
          } else {
            # a sideways link may happen if a node is connected
            # back-to-back with another node
            print "ibnetupdown.pm: ERROR: Level-0 node found to have a sideways link (can't handle this condition)!!\n";
            exit 1;
          }
      } else {
        # link direction is unknown, i don't know whether this
        # is possible, but there is no harm in placing this here
        print "ibnetupdown.pm: WARNING: Unknown link direction for guid:port $guid:$port\n";
      }
    }
  }

  # now, for each switch level, determine link directions and the set
  # of items reachable via purely downlinks
  for(my $lev = 1; $lev < $num_levels; $lev++) {
    foreach my $guid (keys %{$self->{updown}{levels}{$lev}{guids}}) {
      my $g = \%{$self->{updown}{guids}{$guid}};
      $$g{distance}{$guid} = 0;             # the switch can reach itself with a hop distance of 0
      $$g{via_minhop}{$guid}{ports}{0} = 1; # special port 0 to send to myself
      $$g{via_down}{$guid}{ports}{0}   = 1; # special port 0 to send to myself
      foreach my $port ($self->list_connected_ports($guid)) {
        my ($destguid, $destport) = $self->end_point($guid, $port);
        my $dest_g = \%{$self->{updown}{guids}{$destguid}};
        if (defined $$dest_g{level}) {
          if ($$dest_g{level} < $$g{level}) {
            # found a downlink, include each reachable item via down
            # in our down and minhop sets
            $$g{down_ports}{$port} = 1;
            foreach my $n (keys %{$$dest_g{via_down}}) {
              my $dist = $$dest_g{distance}{$n} + 1; # add one to the hop distance
              if (not defined $$g{distance}{$n}) { $$g{distance}{$n} = $dist; }
              if ($dist < $$g{distance}{$n}) {
                # found a shorter path, so delete all previous
                # ports (they are longer)
                delete $$g{via_minhop}{$n}{ports};
                delete $$g{via_down}{$n}{ports};
              }
              if ($dist <= $$g{distance}{$n}) {
                # record the distance and the port used
                $$g{distance}{$n} = $dist;
                $$g{via_minhop}{$n}{ports}{$port} = 1;
                $$g{via_down}{$n}{ports}{$port}   = 1;
              }
            }
          } elsif ($$dest_g{level} > $$g{level}) {
            $$g{up_ports}{$port} = 1;
          } else {
            # found a link that runs sideways in the network,
            # record it for completeness but we don't do anything with this yet
            $$g{side_ports}{$port} = 1;
            print "ibnetupdown.pm: WARNING: Found a sideways link $guid:$port -> $destguid:$destport\n";
            #print "ibnetupdown.pm: ERROR: Found a sideways link (can't handle this condition yet)!!\n";
            #exit 1;
          }
        } else {
          # link direction is unknown
          print "ibnetupdown.pm: WARNING: Unknown link direction for guid:port $guid:$port\n";
        }
      }
    }
  }

  # At this point each item knows which items it can reach via purely
  # downlinks, which gives us down* routing.  Now, work back down the
  # levels to determine which items each item can reach via down links
  # from each of its up-ports.  This will give us all items reachable
  # via purely downlinks from something above us,
  # i.e., up*/down* routing
  for(my $lev = $num_levels-1; $lev >= 1; $lev--) {
    foreach my $guid (keys %{$self->{updown}{levels}{$lev}{guids}}) {
      my $g = \%{$self->{updown}{guids}{$guid}};
      foreach my $port (keys %{$$g{up_ports}}) {
        # for each uplink include each item reachable via minhop in
        # our minhop set
        my ($destguid, $destport) = $self->end_point($guid, $port);
        my $dest_g = \%{$self->{updown}{guids}{$destguid}};
        foreach my $n (keys %{$$dest_g{via_minhop}}) {
          my $dist = $$dest_g{distance}{$n} + 1; # add one to the hop distance
          if (not defined $$g{distance}{$n}) {
            $$g{distance}{$n} = $dist;
          }
          if ($dist < $$g{distance}{$n}) {
            # found a shorter path, so delete all previous
            # ports (they are longer)
            delete $$g{via_minhop}{$n}{ports};
          }
          if ($dist <= $$g{distance}{$n}) {
            # record the distance and the port used
            $$g{distance}{$n} = $dist;
            $$g{via_minhop}{$n}{ports}{$port} = 1;
          }
        }
      }
    }
  }

  # TODO: switches may be able to send to each other via sideways links

  # And, finally we need to march back up once more for the
  # highest-level switches.  The highest-level switches may
  # need to route down then back up to route messages to each
  # other which is strictly minhop and something up*/down*
  # can't do
  for(my $lev = 1; $lev < $num_levels; $lev++) {
    foreach my $guid (keys %{$self->{updown}{levels}{$lev}{guids}}) {
      my $g = \%{$self->{updown}{guids}{$guid}};
      foreach my $port ($self->list_connected_ports($guid)) {
        # for each link include each item reachable via minhop in
        # our own set
        my ($destguid, $destport) = $self->end_point($guid, $port);
        my $dest_g = \%{$self->{updown}{guids}{$destguid}};
        foreach my $n (keys %{$$dest_g{via_minhop}}) {
          my $dist = $$dest_g{distance}{$n} + 1;
          if (not defined $$g{distance}{$n}) {
            $$g{distance}{$n} = $dist;
          }
          if ($dist < $$g{distance}{$n}) {
            # found a shorter path, so delete all previous
            # ports (they are longer)
            delete $$g{via_minhop}{$n}{ports};
          }
          if ($dist <= $$g{distance}{$n}) {
            # record the distance and the port used
            $$g{distance}{$n} = $dist;
            $$g{via_minhop}{$n}{ports}{$port} = 1;
          }
        }
      }
    }
  }
}

1;
