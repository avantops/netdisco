package App::Netdisco::Web::Device;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use URI ();
use Storable 'dclone';
use Scope::Guard 'guard';
use URL::Encode 'url_params_mixed';

hook 'before' => sub {

  # build list of port detail columns
  my @port_columns =
    sort { $a->{idx} <=> $b->{idx} }
    map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
    grep { $_ =~ m/^c_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} };

  # this could be done at app startup?
  splice @port_columns, setting('device_port_col_idx_left'), 0,
    grep {$_->{position} eq 'left'}  @{ setting('_extra_device_port_cols') };
  splice @port_columns, setting('device_port_col_idx_mid'), 0,
    grep {$_->{position} eq 'mid'}   @{ setting('_extra_device_port_cols') };
  splice @port_columns, setting('device_port_col_idx_right'), 0,
    grep {$_->{position} eq 'right'} @{ setting('_extra_device_port_cols') };

  # update sidebar_defaults so code scanning params sees new plugin cols
  setting('sidebar_defaults')->{'device_ports'}->{ $_->{name} } = $_
    for @port_columns;

  var('port_columns' => \@port_columns);

  # build view settings for port connected nodes and devices
  var('connected_properties' => [
    sort { $a->{idx} <=> $b->{idx} }
    map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
    grep { $_ =~ m/^n_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} }
  ]);

  # override ports form defaults with cookie settings
  if (param('reset')) {
    cookie('nd_ports-form' => '', expires => '-1 day');
  }
  elsif (my $cookie = cookie('nd_ports-form')) {
    my $cdata = url_params_mixed($cookie);
    my $defaults = eval { dclone setting('sidebar_defaults')->{'device_ports'} };

    if ($cdata and (ref {} eq ref $cdata) and $defaults) {
      push @{ vars->{'guards'} },
           guard { setting('sidebar_defaults')->{'device_ports'} = $defaults };

      foreach my $key (keys %{ $defaults }) {
        setting('sidebar_defaults')->{'device_ports'}->{$key}->{'default'}
          = $cdata->{$key};
      }
    }
  }
};

hook 'before_template' => sub {
  return if param('reset')
    or not var('sidebar_key') or (var('sidebar_key') ne 'device_ports');

  my $uri = URI->new();
  foreach my $key (keys %{ setting('sidebar_defaults')->{'device_ports'} }) {
    $uri->query_param($key => param($key)) if exists params->{$key};
  }
  cookie('nd_ports-form' => $uri->query(), expires => '365 days');
};

get '/device' => require_login sub {
    my $q = param('q');
    my $devices = schema('netdisco')->resultset('Device');

    # we are passed either dns or ip
    my $dev = $devices->search({
        -or => [
            \[ 'host(me.ip) = ?' => [ bind_value => $q ] ],
            'me.dns' => $q,
        ],
    });

    if ($dev->count == 0) {
        return redirect uri_for('/', {nosuchdevice => 1, device => $q})->path_query;
    }

    # if passed dns, need to check for duplicates
    # and use only ip for q param, if there are duplicates.
    my $first = $dev->first;
    my $others = ($devices->search({dns => $first->dns})->count() - 1);

    params->{'tab'} ||= 'details';
    template 'device', {
      display_name => ($others ? $first->ip : ($first->dns || $first->ip)),
      device => params->{'tab'},
    };
};

true;
