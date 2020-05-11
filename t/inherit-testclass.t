#! perl

use Test2::V0;
use Test2::API 'intercept';

my $events = intercept {
    if ( !defined( do "./t/fixtures/inherit-testclass.it" ) ) {
        die $@ unless $@ eq '';
        die $!;
    }
};

my @events = @$events;

sub check_event {
    my ( $where, $what, $package ) = @_;

    $package ||= $where;
    event(
        'V2' => sub {
            call facet_data => hash {
                field assert => hash {
                    field details => "My::Inherit::${where}::${what}";
                    etc;
                };
                etc;
            };
            prop package => "My::Inherit::${package}";
        } );
}

sub check_subtest {

    my ( $where, $what ) = @_;

    return event(
        'Subtest' => sub {
            call subevents => array {
                check_event( 'Parent' => 'BeforeEach' );
                check_event( 'Child'  => 'BeforeEach' );
                check_event( $where   => $what );
                check_event( 'Parent' => 'AfterEach' );
                check_event( 'Child'  => 'AfterEach' );
                event( 'Plan' );
                end();
            }
        } );
}

# first two events are the BeforeAll events from the parent and child
# classes
is(
    $events[0],
    check_event( Parent => 'BeforeAll', 'SubChild' ),
    "Parent BeforeAll"
);

is(
    $events[1],
    check_event( Child => 'BeforeAll', 'SubChild' ),
    "Child BeforeAll"
);


# last three events are cleanup and plan

is(
    $events[-3],
    check_event( Parent => 'AfterAll', 'SubChild' ),
    "Parent AfterAll"
);
is(
    $events[-2],
    check_event( Child => 'AfterAll', 'SubChild' ),
    "Child AfterAll"
);

is( $events[-1], event( 'Plan' ), "Plan" );


# intermediate events are subtests, skips, or todos, in random order.

my @set = (
    check_subtest( Parent => 'Todo' ),
    check_subtest( Parent => 'Test' ),
    check_subtest( Child  => 'Todo' ),
    check_subtest( Child  => 'Test' ),
    event(
        Skip => sub {
            call name => 'Skip_Parent';
        }
    ),
    event(
        Skip => sub {
            call name => 'Skip_Child';
        }
    ),
);


for my $event ( @events[ 2 .. ( @events - 4 ) ] ) {
    is( $event, in_set( @set ), "Event" );
}


# i've forgotten how to get Perl not to give a used only once error
# for a specific variable
no warnings 'once';

is(
    \@My::Inherit::Parent::EVENTS,
    bag {
        item "My::Inherit::Parent::BeforeAll";
        item "My::Inherit::Child::BeforeAll";

        for ( 1 .. 4 ) {
            item "My::Inherit::Child::AfterEach";
            item "My::Inherit::Child::BeforeEach";
            item "My::Inherit::Parent::AfterEach";
            item "My::Inherit::Parent::BeforeEach";
        }

        item "My::Inherit::Child::Test";
        item "My::Inherit::Child::Todo";

        item "My::Inherit::Parent::Test";
        item "My::Inherit::Parent::Todo";

        item "My::Inherit::Parent::AfterAll";
        item "My::Inherit::Child::AfterAll";

        end;
    },
    "Got the expected events"
);


done_testing;
