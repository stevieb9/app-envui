package App::RPi::EnvUI::DB;

#use Dancer2;
use Dancer2::Plugin::Database;
use Data::Dumper;
use DateTime;
use RPi::WiringPi::Constant qw(:all);

our $VERSION = '0.2';

sub new {
    return bless {}, shift;
}
sub insert_env {
    my ($self, $temp, $hum) = @_;

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

