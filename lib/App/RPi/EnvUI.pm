package App::RPi::EnvUI;

use Async::Event::Interval;
use Dancer2;
use Dancer2::Plugin::Database;
use Data::Dumper;
use DateTime;
use JSON::XS;
use RPi::DHT11;
use RPi::WiringPi::Constant qw(:all);
use WiringPi::API qw(:perl);

our $VERSION = '0.2';

_parse_config();
_reset();
_config_light();

my $env_sensor = RPi::DHT11->new(21);

# set up the pins below the creation of the sensor object...
# this way, WiringPi::API will use GPIO pin numbering scheme,
# as that's the default for RPi::DHT11

my $event_env_to_db = Async::Event::Interval->new(
    _config_core('event_fetch_timer'),
    sub {
        db_insert_env();
    },
);

my $event_action_env = Async::Event::Interval->new(
    _config_core('event_action_timer'),
    sub {
        my $t_aux = env_temp_aux();
        my $h_aux = env_humidity_aux();

        action_temp($t_aux, temp());
        action_humidity($h_aux, humidity());
        action_light(_config_light()) if _config_light('enable');
    }
);

$event_env_to_db->start;
$event_action_env->start;

get '/' => sub {
    # return template 'test';
    return template 'test';

    # the following events have to be referenced to within a route.
    # we do it after return as we don't need this code reached in actual
    # client calls

    my $sensor = $env_sensor;
    my $evt_env_to_db = $event_env_to_db;
    my $evt_action_env = $event_action_env;
};

get '/light' => sub {
    return to_json _config_light();
};

get '/water' => sub {
    return to_json _config_water();
};

get '/get_config/:want' => sub {
    my $want = params->{want};
    my $value = _config_core($want);
    return $value;
};

get '/get_control/:want' => sub {
    my $want = params->{want};
    my $value = _config($want);
    return $value;
};

get '/get_aux/:aux' => sub {
    my $aux_id = params->{aux};
    switch($aux_id);
    return to_json aux($aux_id);
};

get '/set_aux/:aux/:state' => sub {
    my $aux_id = params->{aux};

    my $state = _bool(params->{state});
    $state = aux_state($aux_id, $state);

    my $override = aux_override($aux_id) ? OFF : ON;
    $override = aux_override($aux_id, $override);

    switch($aux_id);

    return to_json {
        aux => $aux_id,
        state => $state,
    };
};

get '/fetch_env' => sub {
    my $data = env();
    return to_json {
        temp => $data->{temp},
        humidity => $data->{humidity}
    };
};
sub switch {
    my $aux_id = shift;

    my $state = aux_state($aux_id);
    my $pin = aux_pin($aux_id);

    if ($pin != 0 && $pin != -1){
        $state
            ? write_pin($pin, HIGH)
            : write_pin($pin, LOW);
    }
}
sub action_light {
    my $light = shift;
    my $now = DateTime->now(time_zone => _config_core('time_zone'));

    my ($on_hour, $on_min) = split /:/, $light->{on_at};

    if ($now->hour > $on_hour || ($now->hour == $on_hour && $now->minute >= $on_min)){
        db_update('light', 'value', time(), 'id', 'on_since');
        aux_state(_config('light_aux'), ON);

        #
        # turn light on here!
        #
    }
    if (_config_light('on_since')){
        my $on_since = _config_light('on_since');
        my $on_hours = _config_light('on_hours');
        my $on_secs = $on_hours * 60 * 60;

        my $time = time();
        my $remaining = $time - $on_since;

        if ($remaining >= $on_secs){
            db_update('light', 'value', 0, 'id', 'on_since');
            aux_state(_config('light_aux'), OFF);

            #
            # turn light off here!
            #
        }
    }
}
sub action_humidity {
    my ($aux_id, $humidity) = @_;

    my $min_run = _config('humidity_aux_on_time');
    my $limit = _config('humidity_limit');

    my $x = aux_override($aux_id);

    if (! aux_override($aux_id)) {
        if ($humidity < $limit && aux_time( $aux_id ) == 0) {
            aux_state( $aux_id, HIGH );
            aux_time( $aux_id, time );
        }
        elsif ($humidity >= $limit && aux_time( $aux_id ) >= $min_run) {
            aux_state( $aux_id, LOW );
            aux_time( $aux_id, 0 );
        }
    }
}
sub action_temp {
    my ($aux_id, $temp) = @_;
    my $limit = _config('temp_limit');
    my $min_run = _config('temp_aux_on_time');

    if (! aux_override($aux_id)){
        if ($temp >= $limit && aux_time($aux_id) == 0){
            aux_state($aux_id, HIGH);
            aux_time($aux_id, time);
        }
        elsif ($temp < $limit && aux_time($aux_id) >= $min_run){
            aux_state($aux_id, LOW);
            aux_time($aux_id, 0);
        }
    }
}
sub aux {
    my $aux_id = shift;

    my $aux_obj
        = database->selectrow_hashref("select * from aux where id='$aux_id'");

    return $aux_obj;
}
sub auxs {
    my $auxs = database->selectall_hashref("select * from aux", 'id');
    return $auxs;
}
sub aux_id {
    return $_[0]->{id};
}
sub aux_state {
    # maintains the auxillary state (on/off)

    my ($aux_id, $state) = @_;
    if (defined $state){
        db_update('aux', 'state', $state, 'id', $aux_id);
    }
    return aux($aux_id)->{state};
}
sub aux_time {
    # maintains the auxillary state (on/off)

    my ($aux_id, $time) = @_;

    if (defined $time) {
        db_update('aux', 'on_time', $time, 'id', $aux_id);
    }

    my $on_time = aux($aux_id)->{on_time};
    return $on_time == 0 ? 0 : time - $on_time;
}
sub aux_override {
    # sets a manual override flag if an aux is turned on manually (via button)

    my ($aux_id, $override) = @_;

    if (defined $override){
        db_update('aux', 'override', $override, 'id', $aux_id);
    }
    return aux($aux_id)->{override};
}
sub aux_pin {
    # returns the auxillary's GPIO pin number

    my ($aux_id, $pin) = @_;
    if (defined $pin){
        db_update('aux', 'pin', $pin, 'id', $aux_id);
    }
    return aux($aux_id)->{pin};
}
sub _config {
    my $want = shift;
    my $env_ctl = database->quick_select('control', {id => $want}, ['value']);
    return $env_ctl->{value};
}
sub _config_core {
    my $want = shift;
    my $core = database->quick_select('core', {id => $want}, ['value']);
    return $core->{value};
}
sub _config_light {
    my $want = shift;

    my $light = database->selectall_hashref("select * from light;", 'id');

    my %conf;

    for (keys %$light) {
        $conf{$_} = $light->{$_}{value};
    }

    my ($on_hour, $on_min) = split /:/, $conf{on_at};

    my $now = DateTime->now(time_zone => _config_core('time_zone'));
    my $light_on = $now->clone;

    $light_on->set_hour($on_hour);
    $light_on->set_minute($on_min);

    my $dur = $now->subtract_datetime($light_on);
    $conf{on_in} = $dur->hours . ' hrs, ' . $dur->minutes . ' mins';

    if (defined $want){
        return $conf{$want};
    }

    return \%conf;
}
sub _config_water {
    my $water = database->selectall_hashref("select * from water;", 'id');

    my %conf;

    for (keys %$water){
        $conf{$_} = $water->{$_}{value};
    }

    return \%conf;
}
sub env {
    my $id = _get_last_id();

    my $row = database->quick_select(
        stats => {id => $id}
    );

    return $row;
}
sub temp {
    return env()->{temp};
}
sub humidity {
    return env()->{humidity};
}
sub env_humidity_aux {
    return _config('humidity_aux');
}
sub env_temp_aux {
    return _config('temp_aux');
}
sub db_insert_env {
    my $temp = $env_sensor->temp('f');
    my $hum = $env_sensor->humidity;

    database->quick_insert(stats => {
            temp => $temp,
            humidity => $hum,
        }
    );
}
sub db_update {
    my ($table, $col, $value, $where_col, $where_val) = @_;
    if (! defined $where_col){
        database->do("UPDATE $table SET $col='$value'");
    }
    else {
        database->do(
            "UPDATE $table SET $col='$value' WHERE $where_col='$where_val'"
        );
    }
}
sub _parse_config {
    my $json;
    {
        local $/;
        open my $fh, '<', 'config/envui.json' or die $!;
        $json = <$fh>;
    }
    my $conf = decode_json $json;

    # auxillary channels

    for (1..8){
        my $aux_id = "aux$_";
        my $pin = $conf->{$aux_id}{pin};
        aux_pin($aux_id, $pin);
    }

    # aux

    for my $directive (keys %{ $conf->{aux} }){
        db_update('aux', 'value', $conf->{aux}{$directive}, 'id', $directive);
    }

    # environment control

    for my $directive (keys %{ $conf->{control} }){
        db_update(
            'control', 'value', $conf->{control}{$directive}, 'id', $directive
        );
    }

    # core configuration

    for my $directive (keys %{ $conf->{core} }){
        db_update('core', 'value', $conf->{core}{$directive}, 'id', $directive);
    }

    # light config

    for my $directive (keys %{ $conf->{light} }){
        db_update('light', 'value', $conf->{light}{$directive}, 'id', $directive);
    }

    # water config

    for my $directive (keys %{ $conf->{water} }){
        db_update('water', 'value', $conf->{water}{$directive}, 'id', $directive);
    }

}
sub _reset {
    # reset dynamic db attributes
    aux_time('aux1', 0);
    aux_time('aux2', 0);
    aux_time('aux3', 0);
    aux_time('aux4', 0);
    aux_time('aux5', 0);
    aux_time('aux6', 0);
    aux_time('aux7', 0);
    aux_time('aux8', 0);
}
sub _bool {
    # translates javascript true/false to 1/0

    my $bool = shift;
    return $bool eq 'true' ? 1 : 0;
}
sub _get_last_id {
    my $id = database->selectrow_arrayref(
        "select seq from sqlite_sequence where name='stats';"
    )->[0];
    return $id;
}

true;
__END__

=head1 NAME

App::RPi::EnvUI - One-page asynchronous grow room environment control web application

=head1 SYNOPSIS

    sudo plackup ./envui

=head1 DESCRIPTION

This distribution is alpha. It does not install the same way most CPAN modules
install, and has some significant requirements Most specifically, the
L<wiringPi|http://wiringpi.com> libraries, and the fact it can only run on a
Raspberry Pi. To boot, you have to have an elaborate electrical relay
configuration set up etc.

Right now, I'm testing an L<App::FatPacker> install method, where the packed 
web app is bundled into a single file called C<envui>, and placed in your
current working directory. See L</SYNOPSIS> for running the app. I doubt this
will work as expected on my first try.

It's got no tests yet, and barely any documentation. It's only here so I can
begin testing the installation routine.

This is my first web app in many, many years, so the technologies (jQuery,
L<Dancer2> etc) are brand new to me, so as I go, I'll be refactoring heavily as
I continue to learn.

At this stage, after I sort the installer, I will be focusing solely on tests.
After tests are done, I'll clean up the code (refactor), then complete the
existing non-finished functionality, and add the rest of the functionality I
want to add.

I'll then add pictures, diagrams and schematics of my physical layout of the Pi
all electrical components, and the electrical circuits.

=head1 WHAT IT DOES

Reads temperature and humidity data via a hygrometer sensor through the
L<RPi::DHT11> distribution.

It then allows, through a one-page asynchronous web UI to turn on and off
120/240v devices through buttons, timers and reached threshold limits.

For example. We have a max temperature limit of 80F. We assign an auxillary
(GPIO pin) that is connected to a relay to a 120v exhaust fan. Through the
configuration file, we load the temp limit, and if the temp goes above it, we
enable the fan via the GPIO pin.

To prevent the fan from going on/off repeatedly if the temp hovers at the limit,
a minimum "on time" is also set, so by default, if the fan turns on, it'll stay
on for 30 minutes, no matter if the temp drops back below the limit.

Each auxillary has a manual override switch in the UI, and if overridden in the
UI, it'll remain in the state you set.

We also include a grow light scheduler, so that you can connect your light, set
the schedule, and we'll manage it. The light has an override switch in the UI,
but that can be disabled to prevent any accidents.

...manages auto-feeding too, but that's not any where near complete yet.


=head1 AUTHOR

Steve Bertrand, E<lt>steveb@cpan.org<gt>

=head1 LICENSE AND COPYRIGHT

Copyright 2016 Steve Bertrand.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.
