#!/usr/bin/perl -w

package Ym;

use warnings;
use strict;

use Ym;

sub FindParents {
  my ($tree, $href) = @_;

  my $mapfile = $Ym::NETMAP_FILE;

  my %hnet       = ();    # key - short name; value - net
  my %hmask      = ();    # key - short name; value - netmask
  my %hname      = ();    # key - vlan name (ip-address); value - short name
  my %hused      = ();    # key - short name; value - used(1/0)
  my %hrouter    = ();    # key - short name; value - router name
  my %hrouterreg = ();    # key - router name; value - reg in Nagios (1/0)

  open(MAP, $mapfile) || die "Can not open $mapfile : $!\n";

  my $cname = 0;

  # Read $mapfile
  while (<MAP>) {
    my $line = $_;
    chomp $line;
    my @str    = split /\s+/, $line;
    my $vlan   = $str[0];
    my $net    = $str[1];
    my $mask   = $str[2];
    my $router = $str[3] . ".yandex.net";
    my $name   = $vlan;

# There are some default gateways that have no dns name (like core-vlan211.yandex.net).
# Old practice is to call such gateways "simple-vlanNN", but that doesn't make sence to NOC.
# First workaround is to name such gateways like their parents - routers.
# But this idea crashes if one router has several interfaces without dns names.
# In this case we may lose some default gateways and keep only the last one.
# Second workaround is to ignore such gateways and say that we can't find parent for a host. Bad thing.
# At last the third way is to leave gateway's ip address as its name. That's I'am going to do.
# The best way also to ask NOC about such things. May be they should always give dns names to all router's interfaces?
#
#    if ($vlan =~ /([\d]+)\.([\d]+)\.([\d]+)\.([\d]+)/)
#    {
#      $cname++;
#      #$name = "simple-vlan";
#      #$name .= $cname;
#      #$name .= ".yandex.net";
#  #$name = $router;
#  $name = $vlan;
#  # Нужно что-то сделать с адресом, чтобы там был не адрес сети, а адрес интерфейса роутера.
#    } else {
#      $name = $vlan;
#    }
    $hnet{$name}         = $net;
    $hmask{$name}        = $mask;
    $hname{$vlan}        = $name;
    $hused{$name}        = 0;
    $hrouter{$name}      = $router;
    $hrouterreg{$router} = 0;

    #print "LINE: $line\n";
    #print "$name - ($net) ($mask)\n";
    #print "$vlan - ($name)\n";
    #print "$name = ($router)\n";
  }
  close(MAP);

  # Find parent for each defined host
  # Find host ip, get network address using all available masks and
  # compare host network address with current corevlan network address
  my @hlist;
  if (defined($href) && ref($href) eq "ARRAY" && scalar(@$href) > 0) {
    @hlist = @$href;
  }
  else {
    @hlist = (keys %{$tree->{'hosts'}});
  }
  foreach my $h (@hlist) {
    if (!defined($tree->{'hosts'}->{$h})) {
      warn "FindParents: Host $h is not defined\n";
      next;
    }
    my ($name, $aliases, $addrtype, $length, @addrs) = gethostbyname($h);
    next unless defined($addrs[-1]);
    my ($a, $b, $c, $d) = unpack('C4', $addrs[-1]);
    my $ip4 = $a . "." . $b . "." . $c . "." . $d;

    next if ($ip4 eq "213.180.193.24");    # Skip host if it resolves in any.yandex.ru
                                           # Delete existent parent
    if (defined($tree->{'hosts'}->{$h}->{'parents'})) {
      delete $tree->{'hosts'}->{$h}->{'parents'};
    }
    foreach my $corevlan (keys %hmask)     # compare ip4 with vlans
    {
      next unless $hmask{$corevlan} =~ /0x(\w\w)(\w\w)(\w\w)(\w\w)/o;
      next if ($corevlan eq $h);

      # Convert mask to dec
      my $ma     = "0x" . $1;
      my $mb     = "0x" . $2;
      my $mc     = "0x" . $3;
      my $md     = "0x" . $4;
      my $ma_dec = hex($ma);
      my $mb_dec = hex($mb);
      my $mc_dec = hex($mc);
      my $md_dec = hex($md);

      # ip4 & mask_dec
      my $ma0      = $a & $ma_dec;
      my $mb0      = $b & $mb_dec;
      my $mc0      = $c & $mc_dec;
      my $md0      = $d & $md_dec;
      my $ip4_mask = $ma0 . "." . $mb0 . "." . $mc0 . "." . $md0;

      # Compare with net of vlan and add parent directive to host if success
      if ($ip4_mask eq $hnet{$corevlan}) {
        $tree->{'hosts'}->{$h}->{'parents'} = $corevlan;
        $hused{$corevlan} = 1;
        last;
      }
    }
  }

  # Delete unused corevlans and define actual corevlans
  # Define hostgroup_name vlan-servers
  #delete $tree->{'hostgroups'}{'vlan-servers'};
  if (!defined($tree->{'hostgroups'}->{'vlan-servers'})) {
    %{$tree->{'hostgroups'}->{'vlan-servers'}} = (
      'hostgroup_name' => 'vlan-servers',
      'alias'          => 'vlan-servers',
    );
  }
  my @members = "";
  if ( defined($tree->{'hostgroups'}->{'vlan-servers'})
    && defined($tree->{'hostgroups'}->{'vlan-servers'}->{'members'}))
  {
    @members = split ",", $tree->{'hostgroups'}->{'vlan-servers'}->{'members'};
    if ($members[-1] eq "") {
      delete($members[-1]);
    }
  }

  # Mark all vlan-servers members as "used" if we are not going to update parents for all hosts
  if (defined($href) && ref($href) eq "ARRAY" && scalar(@$href) > 0) {
    foreach (@members) {
      $hused{$_} = 1;
    }
  }
  my %actual_vlans;    # actual corevlans

  # Remove unused corevlans definitions
  foreach my $name (@members) {
    if (!defined($hname{$name}) || !$hused{$hname{$name}})    # remove unused vlans
    {
      if (defined($tree->{'hosts'}->{$name})) {
        delete($tree->{'hosts'}->{$name});
      }
      next;
    }
    $actual_vlans{$name} = 1;
  }
  while (my ($name, $u) = each %hused) {
    if ($u == 1) {
      $actual_vlans{$name} = 1;
    }
  }
  $tree->{'hostgroups'}->{'vlan-servers'}->{'members'} = join ",", sort keys %actual_vlans;

  # Generate definitions for actual corevlans
  foreach my $name (keys %actual_vlans) {
    my $router = $hrouter{$hname{$name}};
    my $ctgr   = "noc-admins";
    %{$tree->{'hosts'}->{$name}} = (
      'host_name'      => $hname{$name},
      'address'        => $name,
      'alias'          => $hname{$name},
      'contact_groups' => $ctgr,
      'parents'        => $router,
      'use'            => 'corevlan-host',
    );
    %{$tree->{'hosts'}->{$name}->{'services'}->{'coreping'}} = (
      'service_description' => 'coreping',
      'host_name'           => $hname{$name},
      'contact_groups'      => $ctgr,
      'use'                 => 'coreping-vlan-service',
    );

    if (!defined($tree->{'hosts'}->{$router}))    # If parent router is undefined
    {

      # Generate definitions for parent router
      %{$tree->{'hosts'}->{$router}} = (
        'host_name'      => $router,
        'address'        => $router,
        'alias'          => $router,
        'contact_groups' => $ctgr,
        'use'            => 'router-host',
      );
      %{$tree->{'hosts'}->{$router}->{'services'}->{'ping'}} = (
        'service_description' => 'ping',
        'host_name'           => $router,
        'contact_groups'      => $ctgr,
        'use'                 => 'coreping-vlan-service',
      );
    }
  }

  # Remove vlan-servers hostgroup if it is empty.
  if (defined($tree->{'hostgroups'}->{'vlan-servers'})) {
    if (defined($tree->{'hostgroups'}->{'vlan-servers'}->{'members'})
      && $tree->{'hostgroups'}->{'vlan-servers'}->{'members'} ne '')
    {
      my @mem = split(',', $tree->{'hostgroups'}->{'vlan-servers'}->{'members'});
      if (scalar(@mem) == 0) {
        delete($tree->{'hostgroups'}->{'vlan-servers'});
      }
    }
    else {
      delete($tree->{'hostgroups'}->{'vlan-servers'});
    }
  }
}

sub GenerateDependencies {

# If there are some network problems we don't want to execute active service checks
# which are connected with unstable network segment. Also we want to suppress
# notifications from such service alerts. In case they are occured because of network problems.
# Service dependencies will help us.
# We want to generate service dependency for each active service (active_checks_enabled=1 in nagios configs).
# If host's default gateway is alive, than OK, we shall execute active service checks and send
# notifications. If host's network is unreachable from nagios host, block active service checks
# and notifications.

  sub ActiveChecksEnabled;    # Function prototype definition for recursion calls.
      # Determine if active service checks are enabled for specified object.
      # If there is no clear definition, than we recursively look in templates.

  sub ActiveChecksEnabled {
    my ($tree, $leaf) = @_;
    my $ret = 0;
    if (defined($leaf->{'active_checks_enabled'})) {
      $ret = $leaf->{'active_checks_enabled'};
    }
    else {
      if (defined($leaf->{'use'})) {
        my $template = $leaf->{'use'};
        if (!defined($tree->{'service_templates'}->{$template})) {
          return $ret;
        }
        my $template_ref = $tree->{'service_templates'}->{$template};
        $ret = ActiveChecksEnabled($tree, $template_ref);
      }
    }
    return $ret;
  }

  my $tree = shift;
  my %store;    # key - hostname; value - massive of active checks

  foreach my $h (keys %{$tree->{'hosts'}}) {
    foreach my $srv (keys %{$tree->{'hosts'}->{$h}->{'services'}}) {
      my $srv_ref = $tree->{'hosts'}->{$h}->{'services'}->{$srv};
      if (ActiveChecksEnabled($tree, $srv_ref)) {
        push @{$store{$h}}, $srv;
      }
    }
  }

  # Exclude hosts which are in noc-servers or vlan-servers hostgroups
  foreach my $g (qw/vlan-servers noc-servers/) {
    next unless defined($tree->{'hostgroups'}->{$g});
    my @members = split ",", $tree->{'hostgroups'}->{$g}->{'members'};
    foreach my $h (@members) {
      if (defined($store{$h})) {
        delete $store{$h};
      }
    }
  }

  my %corevlan;
  if ( defined($tree->{'hostgroups'}->{'vlan-servers'})
    && defined($tree->{'hostgroups'}->{'vlan-servers'}->{'members'}))
  {
    my @vlans = split ",", $tree->{'hostgroups'}->{'vlan-servers'}->{'members'};
    foreach my $h (@vlans) {
      $corevlan{$h} = 1;    # Init
    }
  }

  # Walk througt all defined service dependencies and delete unclear
  foreach my $dep_host (keys %{$tree->{'service_dependencies'}}) {
    while (my ($dep_id, $dep) =
      each %{$tree->{'service_dependencies'}->{$dep_host}->{'service_dependencies'}})
    {
      # If master host is undef or if it is a core vlan - delete dependency
      my $mh = $dep->{'host_name'};
      if (!defined($tree->{'hosts'}->{$mh}) || defined($corevlan{$mh})) {
        delete($tree->{'service_dependencies'}->{$dep_host}->{'service_dependencies'}->{$dep_id});
      }
    }

    # Cleanup and reorder dependency numbers
    my @dep_ref;
    foreach
      my $cur_dep_ref (values %{$tree->{'service_dependencies'}->{$dep_host}->{'service_dependencies'}})
    {
      push @dep_ref, $cur_dep_ref;
    }
    if (scalar(@dep_ref) > 0) {
      my $c = 0;
      my %refs;
      foreach my $r (@dep_ref) {
        $refs{$c} = $r;
      }
      $tree->{'service_dependencies'}->{$dep_host}->{'service_dependencies'} = \%refs;
    }
    else {
      delete($tree->{'service_dependencies'}->{$dep_host});
    }
  }

  # Add dependency for all hosts that have special service "META"
  foreach my $h (keys %{$tree->{'hosts'}}) {
    if (defined($tree->{'hosts'}->{$h}->{'services'}->{'META'})) {
      push @{$store{$h}}, "META";
    }
  }

  # Make new dependencies
  foreach my $h (keys %store) {
    foreach my $s (@{$store{$h}}) {
      next unless defined($tree->{'hosts'}->{$h}->{'parents'});
      my @parents = split ",", $tree->{'hosts'}->{$h}->{'parents'};
      my %new_dep = (
        'dependent_host_name'           => $h,
        'dependent_service_description' => $s,
        'host_name'                     => $parents[0],
        'service_description'           => 'coreping',
        'inherits_parent'               => 0,
        'execution_failure_criteria'    => 'u,c',
        'notification_failure_criteria' => 'u,c',
      );
      my $c = scalar keys %{$tree->{'service_dependencies'}->{$h}->{'service_dependencies'}};
      $tree->{'service_dependencies'}->{$h}->{'service_dependencies'}->{$c} = \%new_dep;
    }
  }
  return 1;
}

sub VlanContactGroup {
  my $tree    = shift;
  my $vlnr    = $Ym::VLAN_RESPS;
  my %vlans;    # Hash to store vlan number and responsibles from vlan_resps.

  # Load values from vlan_resps into hash.
  open(VRESP, "<$vlnr") or die "Can't open $vlnr : $!\n";
  while (<VRESP>) {
    next unless /^(\S+)\s+(\S+),$/o;
    $vlans{$1} = $2;
  }
  close(VRESP);

  # Retrieve and delete all vlan.*-admins contact groups and its members
  foreach my $ctgr (keys %{$tree->{'contactgroups'}}) {
    if ($tree->{'contactgroups'}->{$ctgr}->{'contactgroup_name'} =~ /(vlan\S+)-admins/o) {
      foreach my $contact (split ",", $tree->{'contactgroups'}->{$ctgr}->{'members'}) {

        delete($tree->{'contacts'}->{$contact});
      }
      delete($tree->{'contactgroups'}->{$ctgr});
    }
  }
  my @corevlans = [];
  if ( defined($tree->{'hostgroups'}->{'vlan-servers'})
    && defined($tree->{'hostgroups'}->{'vlan-servers'}->{'members'}))
  {
    @corevlans = split ",", $tree->{'hostgroups'}->{'vlan-servers'}->{'members'};
  }

  # Generate host and contact template
  if (!defined($tree->{'host_templates'}->{'corevlan-host'})) {
    %{$tree->{'host_templates'}->{'corevlan-host'}} = (
      'use'                   => 'default-host',
      'name'                  => 'corevlan-host',
      'notification_interval' => 30,
      'notification_options'  => 'd,r,u',
      'register'              => 0,
    );
  }
  if (!defined($tree->{'contact_templates'}->{'vlan-sms'})) {
    %{$tree->{'contact_templates'}->{'vlan-sms'}} = (
      'use'                        => 'person-sms',
      'name'                       => 'vlan-sms',
      'host_notification_options'  => 'd,u,r',
      'host_notification_commands' => 'vlan-notify-by-sms',
      'register'                   => 0,
    );
  }

  # Generate contact_group definitions and assign new template for corevlans
  foreach my $cv (@corevlans) {
    next unless ($cv =~ /^core-(\w+).*(\d\d\d)/o);
    my ($dc, $vln) = ($1, $2);
    if ($dc !~ /^dc/ && "$dc" ne "spb") {
      $dc = "dc$dc";
    }
    my $entry   = "vlan${vln}_${dc}";
    my $cv_ctgr = "${entry}-admins";
    $tree->{'hosts'}->{$cv}->{'contact_groups'} .= ",$cv_ctgr";

    my @users;
    my @users_vlan;
    if (defined($vlans{$entry})) {
      @users = split ",", $vlans{$entry};
      foreach my $u (split ",", $vlans{$entry}) {
        push @users_vlan, "${u}-vlan";
      }
    }
    else {
      push @users,      "none";
      push @users_vlan, "none-vlan";
    }
    my $user_list = join ",", @users_vlan;

    # Generate contactgroups definitions
    if (!defined($tree->{'contactgroups'}->{$cv_ctgr})) {
      %{$tree->{'contactgroups'}->{$cv_ctgr}} = (

        #  'use'   => 'corevlan-host',
        'contactgroup_name' => $cv_ctgr,
        'alias'             => "$entry Admins",
        'members'           => $user_list,
      );
    }

    # Generate contacts definitions
    foreach my $contact (@users) {
      my $contact_name = "${contact}-vlan";
      if (!defined($tree->{'contacts'}->{$contact_name})) {
        %{$tree->{'contacts'}->{$contact_name}} = (
          'use'          => 'vlan-sms',
          'contact_name' => $contact_name,
          'alias'        => "$contact Vlan",
          'pager'        => "${contact}-mobile\@monitor.yandex.ru",
        );
      }
    }
  }
  return 1;
}

sub ReadMulcaCfg {
  # Read and parse mulca configuration file. Unit members and baida ports.

  my $cfg     = $Ym::MULCA_UNITS;
  open(MU, "<$cfg") or die "Can't open $cfg : $!\n";

  # Massive of config lines. Each line is a massive of four elements.
  # Unit, host, port, type(0 - ham, 1 - spam). Example: 97 mulca97 10000 1
  my @entries;
  while (<MU>) {
    next unless (/^(\d+)\s+(\S+)\s+(\d+)\s+(\d)/o);
    my @defs = ($1, $2, $3, $4);
    push @entries, \@defs;
  }
  close(MU);

  return \@entries;
}

sub GenerateMulcaActive {
  # Generate mulca hosts, services, cluster hosts and cluster checks for active monitoring.

  my $tree    = shift;
  my $entries = ReadMulcaCfg;
  my $domain  = ".mail.yandex.net";

  # Generate definitions of real mulca hosts and their services (default and baida_port checks).
  my %host_port;    # key - real mulca hosts, value - massive of alive baida ports.

  foreach my $mr (@{$entries}) {
    my $h = "$mr->[1]" . "$domain";
    push @{$host_port{$h}}, $mr->[2];
  }

  my %group_members; # key - real hosts, value = 1 - fake value. 
                     # Store all members of mail-servers hostgroup.

  my $group = "mail-servers";    # hostgroup where mulca hosts are usually defined

  if (defined($tree->{'hostgroups'}->{$group})) {
    my @members = split ",", $tree->{'hostgroups'}->{$group}->{'members'};
    foreach my $member (@members) {
      $group_members{$member} = 1;
    }
  }
  foreach my $h (keys %host_port) {
    if (defined($tree->{'hosts'}->{$h})) {

      # If host is defined than check out if all its baida_XXXX checks are actual.
      my @services = keys %{$tree->{'hosts'}->{$h}->{'services'}};
      my %ports;
      foreach my $p (@{$host_port{$h}}) {
        $ports{$p} = 1;
      }
      foreach my $srv (@services) {
        if ($srv =~ /baida_(\d+)/o) {
          if (!defined($ports{$1})) {
            delete($tree->{'hosts'}->{$h}->{'services'}->{$srv});
          }
        }
      }
    }
    else {

      # If host is absent than we should add it.
      %{$tree->{'hosts'}->{$h}} = (
        'host_name' => $h,
        'address'   => $h,
        'alias'     => $h,
        'use'       => 'mulca-host',
      );

      # Add host to hostgroup
      $group_members{$h} = 1;

      # Add default service checks
      foreach my $srv (@Ym::DEFAULT_MULCA_SERVICES) {
        %{$tree->{'hosts'}->{$h}->{'services'}->{$srv}} = (
          'service_description' => $srv,
          'host_name'           => $h,
          'use'                 => "${srv}-service",
        );
      }
    }

    # Add actual checks for baida.
    foreach my $port (@{$host_port{$h}}) {
      my $srv = "baida_$port";

      # Do not touch service definition for existed host because service check is still present
      next if defined($tree->{'hosts'}->{$h}->{'services'}->{$srv});
      %{$tree->{'hosts'}->{$h}->{'services'}->{$srv}} = (
        'service_description' => $srv,
        'host_name'           => $h,
        'use'                 => 'mulca_baida-service',
        'check_command'       => "check_http_port_url!$port!/status",
      );
    }
  }

  # Delete old hostgroup members.
  foreach my $m (keys %group_members) {
    next unless ($m =~ /mulca(\d+)[ab]?$domain/o);
    if (!defined($host_port{$m})) {
      print "Deleting $m\n";
      delete($group_members{$m});
      delete($tree->{'hosts'}->{$m});
    }
  }
  $tree->{'hostgroups'}->{$group}->{'members'} = join ",", keys %group_members;

  # Verify mulca templates
  if (!defined($tree->{'host_templates'}->{'mulca-host'})) {
    %{$tree->{'host_templates'}->{'mulca-host'}} = (
      'use'                   => 'default-host',
      'name'                  => 'mulca-host',
      'contact_groups'        => 'cluster2-admins',
      'notification_interval' => 60,
      'register'              => 0,
    );
  }
  if (!defined($tree->{'service_templates'}->{'mulca_baida-service'})) {
    %{$tree->{'service_templates'}->{'mulca_baida-service'}} = (
      'use'                 => 'default-service',
      'service_description' => 'mulca_baida-service',
      'contact_groups'      => 'none-admins',
      'register'            => 0,
    );
  }
  if (!defined($tree->{'host_templates'}->{'mulca-cluster'})) {
    %{$tree->{'host_templates'}->{'mulca-cluster'}} = (
      'use'            => 'default-host',
      'name'           => 'mulca-cluster',
      'contact_groups' => 'cluster-admins',
      'check_command'  => 'check-host-ok',
      'register'       => 0,
    );
  }
  if (!defined($tree->{'service_templates'}->{'mulca_baida_cluster-service'})) {
    %{$tree->{'service_templates'}->{'mulca_baida_cluster-service'}} = (
      'use'            => 'cluster-service',
      'name'           => 'mulca_baida_cluster-service',
      'contact_groups' => 'cluster-admins',
      'register'       => 0,
    );
  }

  # Generate mulca cluster hosts and checks
  my %mulca_clusters; # key - cluster host, value - hash 
                      # ( key - real host, value - baida port for unit).

  foreach my $mr (@{$entries}) {
    my $cluster = "mulca" . $mr->[0] . "_cluster";
    my $h       = "$mr->[1]" . "$domain";
    $mulca_clusters{$cluster}->{$h} = $mr->[2];
  }

  %group_members = (); # key - cluster hosts, value = 1 - fake value. 
                       # Store all members of hostgroup.
  $group = "cluster-servers";    # hostgroup where mulca clusters are usually defined

# As I'am writing this there are some mulca clusters that are not clusters but real hosts.
# They are placed in cluster-service group and have appropriate baida_cluster service check which
# refers to themselves. That's too bad. I decided no name all mulca clusters like "mulca55_cluster".
# In this case mulca cluster and real mulcas will always have different names.

# Get list of group members. Do not include mulca cluster hosts in it.
# If any mulca cluster host consist of one real host than keep it. Than delete all other mulca clusters.

  if (defined($tree->{'hostgroups'}->{$group})) {
    my @members = split ",", $tree->{'hostgroups'}->{$group}->{'members'};
    foreach my $member (@members) {
      if ($member =~ /(mulca\d+)/o) {
        my $unit = "${1}_cluster";
        if ($member =~ /mulca\d+ab$domain/o) {
          delete($tree->{'hosts'}->{$member});
        }
        else {
          next unless (defined($tree->{'hosts'}->{$member}->{'services'}->{'baida_cluster'}));
          delete($tree->{'hosts'}->{$member}->{'services'}->{'baida_cluster'});
          if (scalar keys %{$tree->{'hosts'}->{$member}->{'services'}} == 0) {
            delete($tree->{'hosts'}->{$member});
          }
        }

        #  if (scalar keys %{$mulca_clusters{$unit}} == 1)
        #  {
        #    #print "Skipping $member\n";
        #    if (defined($tree->{'hosts'}{$member}{'services'}{'baida_cluster'}))
        #    {
        #    delete($tree->{'hosts'}{$member}{'services'}{'baida_cluster'});
        #    }
        #    # Delete old style mulca cluster hosts ka mulcaXXXab.mail.yandex.net
        #    if ($member =~ /mulca\d+ab$domain/o)
        #    {
        #    delete($tree->{'hosts'}{$member});
        #    }
        #    next;
        #  }
        #  delete($tree->{'hosts'}{$member});
      }
      else {
        $group_members{$member} = 1;
      }
    }
  }

  # Generate mulca clusters
  foreach my $h (keys %mulca_clusters) {

    # Prepare cluster check
    my $c                 = 0;
    my $params            = "-f";
    my $check_command_def = "check_cluster!-s baida!$params!";
    my @p;

    while (my ($real, $port) = each %{$mulca_clusters{$h}}) {
      push @p, "${real}:baida_${port}";
      ++$c;
    }
    next if ($c == 0);
    $check_command_def .= "-w 1!-c $c!-o " . join(",", @p);

    # Add cluster host
    %{$tree->{'hosts'}->{$h}} = (
      'host_name' => $h,
      'address'   => $h,
      'alias'     => $h,
      'use'       => 'mulca-cluster',
    );

    # Add cluster to hostgroup
    $group_members{$h} = 1;

    # Add cluster check
    my $srv = "baida_cluster";
    %{$tree->{'hosts'}->{$h}->{'services'}->{$srv}} = (
      'service_description' => $srv,
      'host_name'           => $h,
      'use'                 => 'mulca_baida_cluster-service',
      'check_command'       => $check_command_def,
    );

  }
  $tree->{'hostgroups'}->{$group}->{'members'} = join ",", keys %group_members;

  return 1;
}

sub GenMiscsearchChecks {
  my ($tree, $mode) = @_;

  if ($mode !~ /active|passive/o) {
    warn("GenMiscsearchChecks: invalid value of second parameter!\n");
    return 1;
  }
  my $template = "miscsearch-service";

# Read and parse miscsearch config file. Find out what service checks should be present on particular host.
  my $cfg     = $Ym::MISCSEARCH_CFG;

  open(CFG, "<$cfg") or die "Can't open $cfg : $!\n";
  my %host_port;    # key - hostname; value - hash of (key - port numver, value - fake value)
  my $domain = ".yandex.ru";
  while (<CFG>) {
    next unless (/^(\d+):([\w\d\s-]+)$/o);
    my $port = $1;
    my @hosts = split " ", $2;
    foreach my $h (@hosts) {
      $host_port{"${h}$domain"}->{$port} = 1;
    }
  }
  close(CFG);

  # Verify checks
  foreach my $h (keys %{$tree->{'hosts'}}) {
    next unless ($h =~ /^ms\d+-\d{3}\.yandex\.ru$/o);

    # Delete old checks
    foreach my $port (keys %Ym::MISCSEARCH_SERVICES) {
      my $srv = "$Ym::MISCSEARCH_SERVICES{$port}_search_$port";

      if (defined($tree->{'hosts'}->{$h}->{'services'}->{$srv})
        && !defined($host_port{$h}->{$port}))
      {
        print "Deleting $h -> $srv\n";
        delete($tree->{'hosts'}->{$h}->{'services'}->{$srv});
      }
    }
  }

  # Add new checks
  foreach my $h (keys %host_port) {
    next unless defined($tree->{'hosts'}->{$h});
    foreach my $port (keys %{$host_port{$h}}) {
      next unless defined($Ym::MISCSEARCH_SERVICES{$port});
      my $srv = "$Ym::MISCSEARCH_SERVICES{$port}_search_$port";
      next if (defined($tree->{'hosts'}->{$h}->{'services'}->{$srv}));

      %{$tree->{'hosts'}->{$h}->{'services'}->{$srv}} = (
        'service_description' => $srv,
        'host_name'           => $h,
        'use'                 => $template,
      );
      if ($mode eq "active") {
        my $cmd;
        if ($port == 17309) {
          $cmd = "check_http_port!$port";

        }
        elsif ($port == 17310) {
          $cmd = "check_miscsearch_music!$port";

        }
        elsif ($port == 17092) {
          $cmd = "check_miscsearch_ruslang!$port";

        }
        elsif ($port == 17093) {
          $cmd = "check_misc_ruslang_wizard!$port";

        }
        elsif ($port == 17072) {
          $cmd = "check_miscsearch_encycl!$port";

        }
        elsif ($port == 17312) {
          $cmd = "check_tcp!$port";

        }
        elsif ($port == 17313) {
          $cmd = "check_miscsearch_verdict!$port";
        }
        elsif ($port == 17314) {
          $cmd = "check_miscsearch_ymusic!$port";
        }
        elsif ($port == 17315) {
          $cmd = "check_miscsearch_coding";
        }
        else {
          $cmd = "check_miscsearch!$port";
        }
        $tree->{'hosts'}->{$h}->{'services'}->{$srv}->{'check_command'} = $cmd;
      }
    }
  }

  # Verify template
  if (!defined($tree->{'service_templates'}->{'miscsearch-service'})) {
    if ($mode eq "active") {
      %{$tree->{'service_templates'}->{'miscsearch-service'}} = (
        'name'                  => $template,
        'use'                   => 'default-service',
        'max_check_attempts'    => 5,
        'contact_groups'        => 'search-admins',
        'event_handler'         => 'set_event',
        'event_handler_enabled' => 1,
        'register'              => 0,
      );
    }
    elsif ($mode eq "passive") {
      %{$tree->{'service_templates'}->{'miscsearch-service'}} = (
        'name'           => $template,
        'use'            => 'passive2-service',
        'contact_groups' => 'yandex-ms-admins,market-admins',
        'register'       => 0,
      );
    }
  }

  return 1;
}

sub CountElements {
  my ($tree) = @_;

  foreach my $el (sort keys %$tree) {
    my $count = scalar keys %{$tree->{$el}};
    my $cc    = 0;
    printf "%30s\t\t%10d", $el, $count;
    if ($el =~ /hosts|service_dependencies/o) {
      my $k = ($el eq "hosts") ? "services" : "service_dependencies";
      foreach my $e (keys %{$tree->{$el}}) {
        $cc += scalar keys %{$tree->{$el}->{$e}->{$k}};
      }
      print " $cc";
    }
    print "\n";
  }
  print "\n";
}

sub GenerateSpecific {
  my ($tree, $host) = @_;

  if ($host eq "dnepr.yandex.ru") {
    GenerateMulcaActive($tree);
    FindParents($tree, "ALL");
    GenerateDependencies($tree);
    VlanContactGroup($tree);

  }
  elsif ($host eq "ussuri.yandex.ru") {
    GenMiscsearchChecks($tree, "active");
    FindParents($tree, "ALL");
    GenerateDependencies($tree);
    VlanContactGroup($tree);

  }
  elsif ($host eq "dvina.yandex.ru") {
    # Do nothing
  }
  else {
    FindParents($tree, "ALL");
    GenerateDependencies($tree);
    VlanContactGroup($tree);
  }
}

1;
