# Copyright (c) 2015, Lawrence Livermore National Security, LLC.
# Produced at the Lawrence Livermore National Laboratory.
# Written by Adam Moody <moody20@llnl.gov>.
# LLNL-CODE-667975.
# All rights reserved.
# This file is part of the IBTopo packag.
# For details, see https://github.com/hpc/ibtopo
# Please also read the LICENSE file.

package ibnetdiscover;
use strict;

# This package reads in and parses an ibnetdiscover file and
# exposes its contents via an API
#   /usr/sbin/ibnetdiscover > ibnetdiscover.2009-09-22.atlas
#
# Author: Adam Moody <moody20@llnl.gov>

# create a new object
#  $ibnet = new ibnetdiscover($ibnetdiscover_file)
sub new
{
  my $type = shift;
  my $file = shift;
  my $self = {};
  $self->{guids}    = {};
  $self->{names}    = {};
  $self->{hcas}     = {};
  $self->{switches} = {};
  read_ibnetdiscover_file($self, $file);
#remove_odd_nodes_and_leaf_switches($self);
  return bless $self, $type;
}

# return the number of guids from the file
#  $num_guids = $ibnet->num_guids()
sub num_guids
{
  my $self = shift;
  return scalar(keys %{$self->{guids}});
}

# return the list of guids from the file
#  @list_guids = $ibnet->list_guids()
sub list_guids
{
  my $self = shift;
  return (keys %{$self->{guids}});
}

# return the number of guids for hcas
#  $num_hca_guids = $ibnet->num_hcas()
sub num_hcas
{
  my $self = shift;
  return scalar(keys %{$self->{hcas}});
}

# return the list of guids for hcas
#  @list_hca_guids = $ibnet->list_hcas()
sub list_hcas
{
  my $self = shift;
  return (keys %{$self->{hcas}});
}

# return the number of guids for switches
#  $num_switch_guids = $ibnet->num_switches()
sub num_switches
{
  my $self = shift;
  return scalar(keys %{$self->{switches}});
}

# return the list of guids for switches
#  @list_switch_guids = $ibnet->list_switches()
sub list_switches
{
  my $self = shift;
  return (keys %{$self->{switches}});
}

# given a guid, return the name of the object
#  $name = $ibnet->name($guid)
sub name
{
  my $self = shift;
  my $guid = shift;
  if (defined $self->{guids}{$guid} and defined $self->{guids}{$guid}{name}) {
    return $self->{guids}{$guid}{name};
  }
  return undef;
}

# given a name, return the guid of the object
#  $guid = $ibnet->guid($name)
sub guid
{
  my $self = shift;
  my $name = shift;
  if (not defined $self->{names}{$name}) {
    print "ibnetdiscover.pm: ERROR: No guid found for $name.\n";
    exit 1;
  } elsif (scalar(keys %{$self->{names}{$name}}) > 1) {
    print "ibnetdiscover.pm: ERROR: Multiple guids found for $name.\n";
    exit 1;
  }
  return (keys %{$self->{names}{$name}})[0];
}

# given a guid, return whether it is an hca
#  $is_hca = $ibnet->is_hca($guid)
sub is_hca
{
  my $self = shift;
  my $guid = shift;
  if (defined $self->{guids}{$guid} and defined $self->{guids}{$guid}{type}) {
    return ($self->{guids}{$guid}{type} eq "hca") ? 1 : 0;
  }
  return undef;
}

# return the number of ports (connected and non-connected),
# which is equal to or greater than the number of connected ports returned by num_connected_ports
#  $num_ports = $ibnet->num_ports($guid)
sub num_ports
{
  my $self = shift;
  my $guid = shift;
  if (defined $self->{guids}{$guid} and defined $self->{guids}{$guid}{numports}) {
    return $self->{guids}{$guid}{numports};
  }
  return undef;
}

# given a guid, return the number of connected ports (ports actively connected to another device)
#  $num_connected_ports = $ibnet->num_connected_ports($guid)
sub num_connected_ports
{
  my $self = shift;
  my $guid = shift;
  if (defined $self->{guids}{$guid} and defined $self->{guids}{$guid}{port}) {
    return scalar(keys %{$self->{guids}{$guid}{port}});
  }
  return undef;
}

# given a guid, return the list of connected ports
#  @list_connected_ports = $ibnet->list_connected_ports($guid)
sub list_connected_ports
{
  my $self = shift;
  my $guid = shift;
  if (defined $self->{guids}{$guid} and defined $self->{guids}{$guid}{port}) {
    return (sort {$a <=> $b} keys %{$self->{guids}{$guid}{port}});
  }
  return undef;
}

# given a guid and a port, return the portguid for that port
# TODO: currently only meaningful on hcas
#  $port_guid = $ibnet->portguid($guid, $port_number)
sub portguid
{
  my $self = shift;
  my $guid = shift; 
  my $port = shift;
  if (defined $self->{guids}{$guid} and defined $self->{guids}{$guid}{port}{$port}{guid}) {
    return $self->{guids}{$guid}{port}{$port}{guid};
  }
  print "ibnetdiscover.pm: ERROR: Portguid for port $port on guid $guid is unkwown.\n";
  exit 1;
}

# given a guid and port, return the guid and port number as a list
# for the object on the other side
#  ($dest_guid, $dest_port_number) = $ibnet->end_point($src_guid, $src_port)
sub end_point
{
  my $self = shift;
  my $guid = shift;
  my $port = shift;
  if (defined $self->{guids}{$guid} and defined $self->{guids}{$guid}{port}{$port}{dest}) {
    return split(":", $self->{guids}{$guid}{port}{$port}{dest});
  }
  return undef;
}

####################################
##  ibnetdiscover data  ############
####################################
##
## Topology file: generated on Tue Sep  5 18:01:40 2006
##
## Max of 6 hops discovered
## Initiated from node 0002c902002227b8 port 0002c902002227b9
#
#vendid=0x8f1
#devid=0x5a30
#sysimgguid=0x8f10400411a09
#switchguid=0x8f10400411a08
#Switch  24 "S-0008f104003f1e29"         # "ISR2012/ISR2004 Voltaire sLB-2024" base port 0 lid 742 lmc 0
#[24]    "H-0002c90200247010"[1]         # "atlas35" lid 1252
#[23]    "H-0002c9020024d5f8"[1]         # "atlas34" lid 3640
#[21]    "H-0002c90200246fbc"[1]         # "atlas32" lid 2984
# ...
#[23]    "S-0008f104004125e2"[11]                # "SW6 ISR9024D nodes [60-71]" lid 64
#[22]    "S-0008f10400411df2"[11]                # "SW27 ISR9024D nodes [312-323]" lid 124
#[21]    "S-0008f10400411d40"[11]                # "SW30 ISR9024D nodes [348-359]" lid 103
# ...
#[12]    "S-0008f1040040165b"[6]         # "ISR2012 Voltaire sFB-2012" lid 751
#[11]    "S-0008f1040040165a"[6]         # "ISR2012 Voltaire sFB-2012" lid 750
#[10]    "S-0008f10400401659"[6]         # "ISR2012 Voltaire sFB-2012" lid 749
# ...
#
#vendid=0x2c9
#devid=0x634a
#sysimgguid=0x2c9020025a4ef
#caguid=0x2c9020025a4ec
#Ca      2 "H-0002c9020025a4ec"          # "atlas133"
#[1](2c9020025a4ed)      "S-000b8cffff004663"[2]         # lid 320 lmc 0 "SW12" lid 37 4xSDR
#
#vendid=0x2c9
#devid=0x634a
#sysimgguid=0x2c90200269e87
#caguid=0x2c90200269e84
#Ca      2 "H-0002c90200269e84"          # "atlas132"
#[1](2c90200269e85)      "S-000b8cffff004663"[1]         # lid 448 lmc 0 "SW12" lid 37 4xSDR
sub read_ibnetdiscover_file
{
  my $self     = shift @_;
  my $filename = shift @_;

  if (not -r $filename) {
    print "ibnetdiscover.pm: ERROR: Could not read ibnetdiscover file $filename\n";
    exit 1;
  }

  my $guid = undef;
  open(IN, $filename);
  while(my $line = <IN>)
  {
    chomp $line;
    if ($line =~ /^Switch\s+(\d+)\s+\"([-\w]+)\"\s+#\s*\"(.*)\"/)
    {
      # start of new switch entry
      $guid = $2;
      my $ports = $1;
      my $name  = $3;

      # pull off any leading S- or H- and prepend a 0x to designate hex
      $guid =~ s/S-//;
      $guid =~ s/H-//;
      $guid = "0x" . $guid;

      $self->{guids}{$guid}{type}     = "switch";
      $self->{guids}{$guid}{name}     = $name;
      $self->{guids}{$guid}{numports} = $ports;
      $self->{names}{$name}{$guid} = 1;
      $self->{switches}{$guid} = 1;
      next;
    }
    if ($line =~ /^Ca\s+(\d+)\s+\"([-\w]+)\"\s+\#\s+\"([-\w\s]+)\"/)
    {
      # start of new channel adapter entry
      $guid = $2;
      my $ports = $1;
      my $name  = $3;

      # for hcas, simplify the name
      if ($name =~ /^([-\w\d]+)/) {
        $name = $1;
      }

      # pull off any leading S- or H- and prepend a 0x to designate hex
      $guid =~ s/S-//;
      $guid =~ s/H-//;
      $guid = "0x" . $guid;

      $self->{guids}{$guid}{type}     = "hca";
      $self->{guids}{$guid}{name}     = $name;
      $self->{guids}{$guid}{numports} = $ports;
      $self->{names}{$name}{$guid} = 1;
      $self->{hcas}{$guid} = 1;
      next;
    }
    # pick up the HCA connections, which include a portguid, unlike lines for switches
    #[1](2c9020025e191)      "S-000b8cffff0049c2"[2]         # lid 42 lmc 0 "SW1" lid 10 4xDDR
    if ($line =~ /^\[(\d+)\]\((\w+)\)\s+\"([-\w-]+)\"\[(\d+)\]\s+#.*/) {
      my ($port, $portguid, $destguid, $destport) = ($1, $2, $3, $4);

      # pull off any leading S- or H- and prepend a 0x to designate hex
      $destguid =~ s/S-//;
      $destguid =~ s/H-//;
      $destguid = "0x" . $destguid;

      $self->{guids}{$guid}{port}{$port}{dest} = "$destguid:$destport";
      $self->{guids}{$guid}{port}{$port}{guid} = "$portguid";
      next;
    }
    if ($line =~ /^\[(\d+)\]\s+\"([-\w-]+)\"\[(\d+)\]\s+#[\w\s]+\"(.*)\" lid (\d+)/)
    {
      # port connectivity record
      my ($port, $destguid, $destport, $destname, $destlid) = ($1, $2, $3, $4, $5);

      # pull off any leading S- or H- and prepend a 0x to designate hex
      $destguid =~ s/S-//;
      $destguid =~ s/H-//;
      $destguid = "0x" . $destguid;

      $self->{guids}{$guid}{port}{$port}{dest} = "$destguid:$destport";
      next;
    }
    if ($line =~ /^\[(\d+)\]\s+\"([-\w-]+)\"\[(\d+)\]\(\w+\)\s+#[\w\s]+\"(.*)\" lid (\d+)/)
    {
      # port connectivity record
      my ($port, $destguid, $destport, $destname, $destlid) = ($1, $2, $3, $4, $5);

      # pull off any leading S- or H- and prepend a 0x to designate hex
      $destguid =~ s/S-//;
      $destguid =~ s/H-//;
      $destguid = "0x" . $destguid;

      $self->{guids}{$guid}{port}{$port}{dest} = "$destguid:$destport";
      next;
    }
    if ($line =~ /^\[(\d+)\]\(\w+\)\s+\"([-\w-]+)\"\[(\d+)\]\s+#[\w\s]+\"(.*)\" lid (\d+)/)
    {
      # port connectivity record
      my ($port, $destguid, $destport, $destname, $destlid) = ($1, $2, $3, $4, $5);

      # pull off any leading S- or H- and prepend a 0x to designate hex
      $destguid =~ s/S-//;
      $destguid =~ s/H-//;
      $destguid = "0x" . $destguid;

      $self->{guids}{$guid}{port}{$port}{dest} = "$destguid:$destport";
      next;
    }
  }
  close(IN);
}

sub remove_odd_nodes_and_leaf_switches
{
  my $self     = shift @_;

  # first disconnect all ports connected to oss nodes
  my %bad_leaves = ();
  my @hcas = list_hcas($self);
  foreach my $guid (@hcas) {
    my $name = name($self, $guid);
#    print "$guid $name\n";

    if ($name =~ /^oss/ ||
        $name =~ /^grid/ ||
        $name =~ /^sge/ ||
        $name =~ /^lgw/ ||
        $name =~ /^spur/ ||
        $name =~ /^vis/ ||
        $name =~ /^login/)
    {
       my @ports = list_connected_ports($self, $guid);
       foreach my $port (@ports) {
         my ($destguid, $destport) = end_point($self, $guid, $port);
#         print "$guid $name --> $destguid:$destport\n";
         $bad_leaves{$destguid} = 1;
       }

      # make it though as this node doesn't exist
      delete $self->{guids}{$guid};
      delete $self->{hcas}{$guid};
      delete $self->{names}{$name};
    }
  } 

  # define some other strange switches to remove
  $bad_leaves{"0x00144f0000a4359d"} = 1;
  $bad_leaves{"0x00144f0000a436a1"} = 1;
  $bad_leaves{"0x00144f0000a60aa1"} = 1;
  $bad_leaves{"0x00144f0000a437a6"} = 1;
  $bad_leaves{"0x00144f0000a437da"} = 1;

  $bad_leaves{"0x00144f0000a5f3c8"} = 1;

  foreach my $guid (keys %bad_leaves) {
    my $name = name($self, $guid);
#    print "$guid $name\n";

    my @ports = list_connected_ports($self, $guid);
    foreach my $port (@ports) {
      my ($destguid, $destport) = end_point($self, $guid, $port);
#      print "$guid --> $destguid:$destport\n";

      # disconnect remote end
      if (defined $self->{guids}{$destguid}) {
        delete $self->{guids}{$destguid}{port}{$destport};
      }
    }

    # delete the switch
    delete $self->{guids}{$guid};
    delete $self->{names}{$name};
    delete $self->{switches}{$guid};
  }
}

1;
