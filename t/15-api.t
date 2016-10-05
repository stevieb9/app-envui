use strict;
use warnings;

BEGIN {
    use lib 't/';
    use TestBase;
    config();
}

use App::RPi::EnvUI::API;
use App::RPi::EnvUI::DB;
use Data::Dumper;
use Mock::Sub;
use Test::More;

# mock out some subs that rely on external C libraries

my $mock = Mock::Sub->new;

my $temp_sub = $mock->mock(
    'RPi::DHT11::temp',
    return_value => 80
);

my $hum_sub = $mock->mock(
    'RPi::DHT11::humidity',
    return_value => 20
);

my $wp_sub = $mock->mock(
    'App::RPi::EnvUI::API::write_pin',
    return_value => 'ok'
);

my $api = App::RPi::EnvUI::API->new(testing => 1, config_file => 't/envui.json');
my $db = App::RPi::EnvUI::DB->new(testing => 1);

is ref $api, 'App::RPi::EnvUI::API', "new() returns a proper object";
is $api->{testing}, 1, "testing param to new() ok";

$api->_parse_config;

{ # read_sensor()
    my @env = $api->read_sensor;

    is @env, 2, "mocked read_sensor() returns proper count of values";
    is $env[0], 80, "first elem of return ok (temp)";
    is $env[1], 20, "second elem of return ok (humidity)";
}

{ # aux()

    for (1..8){
        my $name = "aux$_";
        my $aux = $api->aux($name);

        is ref $aux, 'HASH', "aux() returns $name as an href";
        is keys %$aux, 6, "$name has proper key count";

        for (qw(id desc pin state override on_time)){
            is exists $aux->{$_}, 1, "$name has directive $_";
        }
    }

    my $aux = $api->aux('aux9');
    is $aux, undef, "only 8 auxs available";

    $aux = $api->aux('aux0');
    is $aux, undef, "aux0 doesn't exist";
}
{ # auxs()

    my $db_auxs = $db->auxs;
    my $api_auxs = $api->auxs;

    is keys %$api_auxs, 8, "eight auxs() total from auxs()";

    for my $db_k (keys %$db_auxs) {
        for (keys %{ $db_auxs->{$db_k} }) {
            is $db_auxs->{$db_k}{$_}, $api_auxs->{$db_k}{$_},
                "db and api return the same auxs() ($db_k => $_)";
        }
    }
}

{ # aux_id()

    # takes aux hash

    for (1..8){
        my $name = "aux$_";
        my $aux = $api->aux($name);
        my $id = $api->aux_id($aux);

        is $id, $name, "aux_id() returns proper ID for $name";


    }
}

{ # aux_state()

    for (1..8){
        my $aux_id = "aux$_";
        my $state = $api->aux_state($aux_id);

        is $state, 0, "aux_state() returns correct default state value for $aux_id";

        $state = $api->aux_state($aux_id, 1);

        is $state, 1, "aux_state() correctly sets state for $aux_id";

        $state = $api->aux_state($aux_id, 0);

        is $state, 0, "aux_state() can re-set state for $aux_id";
    }

    my $ok = eval { $api->aux_state; 1; };

    is $ok, undef, "aux_state() dies if an aux ID not sent in";
    like $@, qr/requires an aux ID/, "...and has the correct error message";
}

{ #aux_time()

    my $time = time();

    for (1..8){
        my $id = "aux$_";

        is $api->aux_time($id), 0, "aux_time() has correct default for $id";

        $api->aux_time($id, $time);
    }

    sleep 1;

    for (1..8){
        my $id = "aux$_";
        my $elapsed = time() - $api->aux_time($id);
        ok $elapsed > 0, "aux_time() sets time correctly for $id";
        is $api->aux_time($id, 0), 0, "and resets it back again ok";
    }

    my $ok = eval { $api->aux_time(); 1; };

    is $ok, undef, "aux_time() dies if no aux id is sent in";
}

{ # aux_override()

    for (1..8){
        my $aux_id = "aux$_";
        my $o = $api->aux_override($aux_id);

        is $o, 0, "aux_override() returns correct default override value for $aux_id";

        $o = $api->aux_override($aux_id, 1);

        is $o, 1, "aux_override() correctly sets override for $aux_id";

        $o = $api->aux_override($aux_id, 0);

        is $o, 0, "aux_override() can re-set override for $aux_id";
    }

    my $ok = eval { $api->aux_override; 1; };

    is $ok, undef, "aux_override() dies if an aux ID not sent in";
    like $@, qr/requires an aux ID/, "...and has the correct error message";
}

{ # aux_pin()

    for (1..8){
        my $aux_id = "aux$_";
        my $p = $api->aux_pin($aux_id);

        is $p, -1, "aux_pin() returns correct default pin value for $aux_id";

        $p = $api->aux_pin($aux_id, 1);

        is $p, 1, "aux_pin() correctly sets pin for $aux_id";

        $p = $api->aux_pin($aux_id, -1);

        is $p, -1, "aux_pin() can re-set pin for $aux_id";
    }

    my $ok = eval { $api->aux_pin; 1; };

    is $ok, undef, "aux_pin() dies if an aux ID not sent in";
    like $@, qr/requires an aux ID/, "...and has the correct error message";
}

{ # switch()

    for (1..8){
        my $id = "aux$_";
        $api->aux_pin($id, 1);
        my $ret = $api->switch($id);

        is $wp_sub->called, 1, "switch(): wp called if pin isn't -1";
        is $ret, 'ok', "switch(): if pin isn't -1, we call write_pin(), $id";

        $api->aux_pin($id, -1);

        is $api->aux_pin($id), -1, "successfully reset $id pin to -1";
    }

    $wp_sub->reset;

    for (1..8){
        my $id = "aux$_";
        my $ret = $api->switch($id);

        is $wp_sub->called, 0, "switch(): write_pin() not called if pin state is -1: $id";
        is $ret, '', "switch(): if pin is -1, we don't call write_pin(), $id";
    }
}
{ # env()

    my $ret = $api->env(99, 1);

    is $ret->{temp}, 99, "env() w/ params sets temp properly";
    is $ret->{humidity}, 1, "env() w/params sets humidity properly";

    $ret = $api->env;

    is $ret->{temp}, 99, "env() w/o params returns temp ok";
    is $ret->{humidity}, 1, "env() w/o params returns humidity ok";

    $api->env(50, 50);
    $ret = $api->env;

    is $ret->{temp}, 50, "env() does the right thing after another update (temp)";
    is $ret->{humidity}, 50, "env() does the right thing after another update (hum)";

    my $ok = eval { $api->env(50), 1; };
    is $ok, undef, "env() dies if neither 0 or exactly 2 args sent in";
    like $@, qr/requires either/, "...and the error message is correct";

    for (qw(1.1 99h hello !!)){

        $ok = eval { $api->env($_, 99); 1; };
        is $ok, undef, "env() dies if temp arg isn't a number\n";
        like $@, qr/must be an integer/, "...and for temp, error is ok";

        $ok = eval { $api->env(99, $_); 1; };
        is $ok, undef, "env() dies if humidity arg isn't a number\n";
        like $@, qr/must be an integer/, "...and for humidity, error is ok";
    }
}

{ # temp(), humidity()

    for (1..50){
        $api->env($_, $_);
        is $api->temp, $_, "env() update to $_, temp() returns ok";
        is $api->humidity, $_, "env() update to $_, humidity() returns ok";
    }

}

{ # bool()

    my $ok = eval { $api->_bool; 1; };
    is $ok, undef, "bool() dies if a param isn't sent in";
    like $@, qr/'true' or 'false'/, "...and the error is correct";

    is $api->_bool('true'), 1, "bool('true') ok";
    is $api->_bool('false'), 0, "bool('false') ok";

}

{ # _reset()

    for (1..8){
        my $id = "aux$_";
        $api->aux_time($id, 99);
        my $time = $api->aux_time($id);
        ok $time > 0, "_reset() test setup ok for $id";
    }

    $api->_reset;

    for (1..8){
        my $id = "aux$_";
        my $time = $api->aux_time($id);
        is $time, 0, "_reset() sets $id back to 0 on_time";
    }
}

{ # env_temp_aux
    is $api->env_temp_aux, 'aux1', "aux1 is the temp aux by default";
    $db->update('control', 'value', 'aux9', 'id', 'temp_aux');
    is $api->env_temp_aux, 'aux9', "setting the value works ok";
    $db->update('control', 'value', 'aux1', 'id', 'temp_aux');
    is $api->env_temp_aux, 'aux1', "...and works ok going back too";
}

{ # env_temp_humidity
    is $api->env_humidity_aux, 'aux2', "aux2 is the humidity aux by default";
    $db->update('control', 'value', 'aux9', 'id', 'humidity_aux');
    is $api->env_humidity_aux, 'aux9', "setting the value works ok";
    $db->update('control', 'value', 'aux2', 'id', 'humidity_aux');
    is $api->env_humidity_aux, 'aux2', "...and works ok going back too";
}

# $db->{db}->sqlite_backup_to_file('test.db');
unconfig();
done_testing();
