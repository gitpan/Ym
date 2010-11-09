{
  package Ym;

  $YMHOME = '/home/monitor/work/ym';
  $STRUCT_FILE = "$YMHOME/store/config.struct";

  $NAGIOS_CFG_DIR = '/home/monitor/NAGIOS/etc';
  $NAGIOS_CFG_NAME = 'nagios.cfg';
  $NAGIOS_MAIN_CFG = "$NAGIOS_CFG_DIR/$NAGIOS_CFG_NAME";

  $WORKPLACE = "$YMHOME/tmp/etc";

  @NAGIOS_CONFIGS = qw/
    nagios.cfg commands.cfg
    contact-templates.cfg contactgroups.cfg contacts.cfg
    host-templates.cfg hostgroups.cfg
    services.cfg service-templates.cfg
    timeperiods.cfg
    service-dependencies.cfg host-dependencies.cfg
    /;  

  %BRANCHES = (
    'commands'             => ['command',           'commands.cfg'],
    'contact_templates'    => ['contact',           'contact-templates.cfg'],
    'contactgroups'        => ['contactgroup',      'contactgroups.cfg'],
    'contacts'             => ['contact',           'contacts.cfg'],
    'host_templates'       => ['host',              'host-templates.cfg'],
    'hostgroups'           => ['hostgroup',         'hostgroups.cfg'],
    'hosts'                => ['host',              'services.cfg'],
    'service_templates'    => ['service',           'service-templates.cfg'],
    'timeperiods'          => ['timeperiod',        'timeperiods.cfg'],
    'service_dependencies' => ['servicedependency', 'service-dependencies.cfg'],
    'host_dependencies'    => ['hostdependency',    'host-dependencies.cfg'],
    'services'             => ['service',],
  );

  $HOSTNAME = `hostname -f`;
  chomp($HOSTNAME);

  $VERBOSE = 0;
  $DEBUG   = 0;

  $SHOW_DIFF_BY_DEFAULT = 1;

  $BACKUP_CONFIG_FILES = 1;
  $BACKUP_PATH = '/var/backups/ym/nagios_cfg_backup';

  # Yandex specific definitions.

  $ENABLE_YM_SPECIFIC = 1;

  $NETMAP_FILE = "$YMHOME/src/netmap.list";
  $VLAN_RESPS  = "$YMHOME/src/vlan_resps";
  $MULCA_UNITS = "$YMHOME/src/mulca_units";

  # Default services for all real mulca hosts. They all use templates like mtu-service, tcp_94-service
  # All templates should be defined manualy!
  @DEFAULT_MULCA_SERVICES = 
    qw/META hw_errs watchdog cron mtu mulca_clean ntp raid5 ssh workers tcp_94 filesystem_clean/;

  $MISCSEARCH_CFG = "$YMHOME/etc/miscsearch.conf";
  %MISCSEARCH_SERVICES = (
    '17041' => 'news',
    '17042' => 'news',
    '17043' => 'news',
    '17045' => 'news',
    '17046' => 'news',
    '17049' => 'news',
    '17061' => 'afisha',
    '17065' => 'raspisanie',
    '17071' => 'encycl',
    '17072' => 'encycl',
    '17091' => 'books',
    '17092' => 'ruslang',
    '17093' => 'ruslang_wizard',
    '17095' => 'maket_books',
    '17101' => 'dosye',
    '17102' => 'dosierp',
    '17120' => 'antiwizard',
    '17201' => 'blogs',
    '17301' => 'catalog',
    '17303' => 'catalog_ua',
    '17306' => 'wikifacts',
    '17307' => 'moikrug_vac',
    '17309' => 'tv',
    '17310' => 'music',
    '17311' => 'topics',
    '17312' => 'mplayer',
    '17313' => 'verdict',
    '17314' => 'ymusic',
    '17315' => 'coding',
  );
}

