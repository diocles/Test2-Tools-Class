package Test2::Tools::xUnit 0.006;

use v5.12;
use warnings;

use B;
use Test2::Workflow;
use Test2::Workflow::Runner;
use Test2::Workflow::Task::Action;

sub import {
    my @caller = caller;

    # This sets up the root Test2::Workflow::Build for the package we are
    # being called from.  All tests will be added as actions later.
    my $root = Test2::Workflow::init_root(
        $caller[0],
        code  => sub { },
        frame => \@caller,
    );

    # Each test method is run in its own instance.  This setup action will
    # be called before each test method is invoked, and instantiates a new
    # object.
    #
    # If the caller does not provide a "new" constructor, we bless a hashref
    # into the calling package and use that.
    #
    # Each coderef is called with the Test2::Workflow::Runner as the first
    # argument.  We abuse this so that we can pass the same instance variable
    # to the setup, test and teardown methods.
    $root->add_primary_setup(
        Test2::Workflow::Task::Action->new(
            code => sub {
                shift->{xUnit}
                    = $caller[0]->can('new')
                    ? $caller[0]->new
                    : bless {}, $caller[0];
            },
            name     => 'object_construction',
            frame    => \@caller,
            scaffold => 1,
        )
    );

    # We add a follow-up task to the top hub in the stack, which will be
    # executed when done_testing or END is seen.
    Test2::API::test2_stack->top->follow_up(
        sub { Test2::Workflow::Runner->new( task => $root->compile )->run } );

    my $orig = $caller[0]->can('MODIFY_CODE_ATTRIBUTES');

    # This sub will be called whenever the Perl interpreter hits a subroutine
    # with attributes in our caller.
    #
    # It closes over $root so that it can add the actions, and @caller so that
    # it knows which package it's in.
    my $modify_code_attributes;
    $modify_code_attributes = sub {
        my ( $pkg, $code, @attrs ) = @_;

        # In order to pass the correct frame to
        # Test2::Workflow::Task::Action below, search for the
        # package that called the attribute handler. This should
        # be one level above attributes in the caller stack.
        # make sure we don't run off of the stack

        my $level = 0;
        my @test_caller;
        for  ( ; @test_caller = caller( $level ) ; ++$level ) {
            last if $test_caller[0] eq 'attributes';
        }

        # if we've found the proper frame, use that, else default
        # to this package.
        my @caller = @test_caller ? caller(++$level) : @caller;

        my $name = B::svref_2object($code)->GV->NAME;

        my ( $method, $class_method, %options, @unhandled );

        for (@attrs) {
            if ( $_ eq 'Test' ) {
                $method = 'add_primary';
            }
            # All the setup methods count as 'scaffolding'.
            # Test2::Workflow docs are light on what this actually does;
            # something to do with filtering out the events?  Anyway,
            # Test2::Tools::Spec does it.
            elsif ( $_ eq 'BeforeEach' ) {
                $method = 'add_primary_setup';
                $options{scaffold} = 1;
            }
            elsif ( $_ eq 'AfterEach' ) {
                $method = 'add_primary_teardown';
                $options{scaffold} = 1;
            }
            # BeforeAll/AfterAll are called as class methods, not instance
            # methods.
            elsif ( $_ eq 'BeforeAll' ) {
                $method            = 'add_setup';
                $options{scaffold} = 1;
                $class_method      = 1;
            }
            elsif ( $_ eq 'AfterAll' ) {
                $method            = 'add_teardown';
                $options{scaffold} = 1;
                $class_method      = 1;
            }
            # We default to the name of the current method if no reason is
            # given for Skip/Todo.
            elsif (/^Skip(?:\((.+)\))?/) {
                $method = 'add_primary';
                $options{skip} = $1 || $name;
            }
            elsif (/^Todo(?:\((.+)\))?/) {
                $method = 'add_primary';
                $options{todo} = $1 || $name;
            }
            # All unhandled attributes are returned for someone else to
            # deal with.
            else {
                push @unhandled, $_;
            }
        }

        if ($method) {
            my $task = Test2::Workflow::Task::Action->new(
                code => $class_method
                ? sub { $pkg->$code }
                : sub { shift->{xUnit}->$code },
                frame => \@caller,
                name  => $name,
                %options,
            );

            $root->$method($task);
        }

        @_ = ( $pkg, $code, @unhandled );
        if ($orig) {
            goto $orig;
        }
        else {
            # A package like Attribute::Handlers might have modified @ISA
            # after we were imported. Note that SUPER won't work because it
            # finds the compile-time package of this sub.
            no strict 'refs';
            my @parents = @{ $pkg . '::ISA' };
            @parents = 'UNIVERSAL' unless @parents;
            for my $parent (@parents) {

                # if this package is inherited from, need to ensure
                # that we don't just jump right back into this
                # very routine, as that'll generate an infinite loop.
                my $subref = $parent->can('MODIFY_CODE_ATTRIBUTES');
                if ( $subref && $subref != $modify_code_attributes ) {
                    goto $subref;
                }
            }
        }

        return @unhandled;
    };

    no strict 'refs';
    no warnings 'redefine';

    *{"$caller[0]::MODIFY_CODE_ATTRIBUTES"} = $modify_code_attributes;
}

1;
