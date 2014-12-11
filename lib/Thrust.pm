package Thrust;

use common::sense;

our $VERSION = '0.100';

use AnyEvent;
use AnyEvent::Util;
use AnyEvent::Handle;
use JSON::XS;
use File::ShareDir;
use Scalar::Util;

use Thrust::Window;


our $THRUST_PATH = File::ShareDir::dist_dir('Thrust') .  '/thrust_shell';
our $THRUST_BOUNDARY = "\n--(Foo)++__THRUST_SHELL_BOUNDARY__++(Bar)--\n";

sub new {
  my ($class, %args) = @_;

  my $self = {
    action_id => 10,
  };

  bless $self, $class;

  my ($fh1, $fh2) = portable_socketpair();

  $self->{cv} = run_cmd [ $THRUST_PATH ],
                        close_all => 1,
                        '>' => $fh2,
                        '<' => $fh2,
                        '$$' => \$self->{pid};

  close $fh2;

  $self->{fh} = $fh1;

  $self->{hdl} = AnyEvent::Handle->new(fh => $self->{fh});

  my $line_handler; $line_handler = sub {
    my ($hdl, $line) = @_;

    my $msg = eval { decode_json($line) };

    if (defined $msg) {
      if ($msg->{_action} eq 'reply') {
        my $action_cb = $self->{actions}->{$msg->{_id}};
        if ($action_cb) {
          $action_cb->($msg);
        } else {
          warn "reply to unknown request";
        }
      } elsif ($msg->{_action} eq 'event') {
        my $window = $self->{windows}->{$msg->{_target}};

        if ($window) {
          $window->_trigger($msg->{_type}, $msg->{_event});
        }
      }
    }

    $self->{hdl}->push_read(line => $line_handler);
  };

  $self->{hdl}->push_read(line => $line_handler);

  return $self;
}

sub run {
  AE::cv->recv;
}

sub do_action {
  my ($self, $params, $cb) = @_;

  my $action_id = $self->{action_id}++;

  $params->{_id} = $action_id;

  $self->{hdl}->push_write(json => $params);

  $self->{hdl}->push_write($THRUST_BOUNDARY);

  $self->{actions}->{$action_id} = sub {
    delete $self->{actions}->{$action_id};
    $cb->($_[0]->{_result});
  };
}

sub window {
  my ($self, %args) = @_;

  my $window = { thrust => $self, };
  bless $window, 'Thrust::Window';

  $self->do_action({ '_action' => 'create', '_type' => 'window', '_args' => \%args, }, sub {
    my $id = $_[0]->{_target};
    $window->{target} = $id;
    $self->{windows}->{$id} = $window;
    Scalar::Util::weaken $self->{windows}->{$id};
    $window->_trigger_event('ready');
  });

  return $window;
}



sub DESTROY {
  my ($self) = @_;

  kill 'KILL', $self->{pid};
}


1;


__END__

=encoding utf-8

=head1 NAME

Thrust - Perl bindings to the Thrust cross-platform application framework

=head1 SYNOPSIS

    use Thrust;

    my $t = Thrust->new;

    my $w = $t->window(
              root_url => 'data:text/html;charset=utf-8,Hello World!',
              title => 'My App',
              size => { width => 400, height => 400 },
            )->show;

    $t->run;

=head1 DESCRIPTION

Thrust is a chromium-based cross-platform / cross-language application framework. Read more about it at its L<official website|https://github.com/breach/thrust>.

Like the bindings for other languages, installing this module will download a zip file containing the thrust_shell binary and required libraries and will store it in the distribution's share directory.

Unlike the bindings for other languages, in perl we don't have wrapper functions for every method exposed by the thrust shell. This has the advantage that there is generally no need to update the bindings when new methods/parameters are added to the thrust shell, but has the disadvantage that sometimes the API is less convenient. For instance, instead of positional arguments in (for example) the C<move> method, you must use the named C<x> and C<y> parameters.

=head1 ASYNC PROGRAMMING

Like browser programming itself, programming the perl side of a Thrust application is done in an asynchronous style. The Thrust package depends on AnyEvent for this purpose so you can use whichever event loop you prefer. See the L<AnyEvent> documentation for details on asynchronous programming.

The C<run> method of the Thrust context object simply waits on a condition variable that will never be signalled in order to enter the event loop.

Almost all methods on the window object can optionally take a callback argument that will be called once the operation has been completed. For example:

    $w->maximize(sub { say "window has been maximized" });

If present, the callback must be the final argument. For methods that require parameters, the parameters must be in a hash-ref preceeding the (optional) callback:

    $w->resize({ width => 100, height => 100 },
               sub { say "window has been resized" });

Like the bindings in other languages, methods can be invoked on a window object even before the window is created. The methods will be queued up and invoked once the window is ready. Unlike the other bindings, the perl bindings also support method chaining so you can write in a convenient style like so:

    Thrust->new->window->open_devtools->show;

    AE::cv->recv; ## enter event loop

=head1 REMOTE EVENTS AND HANDLERS

One of the most useful features of thrust is its support for bi-directional messaging between your application and the browser. It does this over the control pipes already opened to communicate with the thrust shell so there is no additional setup required such as starting an AJAX/websocket server.

In order for the browser to send a message to your perl code, have it execute something like the following javascript:

    THRUST.remote.send({ foo: 'bar' });

On the perl side, you will need to install an event handler for the C<remote> event by calling the C<on> method of a window object:

    $w->on('remote', sub {
        my $msg = $_[0]->{message};

        print $msg->{foo}; # prints bar
    });

In order to send a message from perl to the browser, call the C<remote> method on a window object:

    $w->remote({ message => { foo => 'bar' } });

On the javascript side, you will need to install a handler like so:

    THRUST.remote.listen(function(msg) {
        console.log(msg['foo']); // prints bar
    });

B<IMPORTANT NOTE>: Before applications can send messages from perl to javascript, the C<THRUST.remote.listen> function must have been called. If you try to send a message before this, it is likely that the message will be delivered to the browser before the handler has been installed so your message will be lost. After they have started and initialised their remote handlers, applications should have javascript send a message to perl indicating that the communication channel is ready and that perl can begin sending messages to the browser.

If you ever wish to remove handlers for an event, window objects also have a C<clear> method:

    $w->clear('remote');

=head1 BUGS

Only the window object is exposed currently. Eventually the window code should be refactored into a base class so that session and menu can be implemented as well (as done in the node.js bindings).

The error handling is pretty poor right now. This is partly due to the fact that the perl bindings are incomplete, and partly due to the fact that the thrust_shell doesn't have great error checking either. Any error messages like the following probably indicate that you passed in some malformed arguments and the thrust_shell terminated abnormally:

    AnyEvent::Handle uncaught error: Broken pipe at /usr/local/lib/perl/5.18.2/AnyEvent/Loop.pm line 248.

=head1 SEE ALSO

L<The Thrust perl module github repo|https://github.com/hoytech/Thrust>

L<The Thrust project|https://github.com/breach/thrust> - Official website

L<The node.js Thrust bindings|https://github.com/breach/node-thrust/> - These are the most complete bindings

=head1 AUTHOR

Doug Hoyte, C<< <doug@hcsw.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2014 Doug Hoyte.

This module is licensed under the same terms as perl itself.

=cut



{"_id":1,"_action":"create","_type":"window","_args":{"root_url":"http://google.com"}}
--(Foo)++__THRUST_SHELL_BOUNDARY__++(Bar)--

{"_action":"reply","_error":"","_id":1,"_result":{"_target":1}}
--(Foo)++__THRUST_SHELL_BOUNDARY__++(Bar)--

{"_id":2,"_action":"call","_target":1,"_method":"show","_args":{}}
--(Foo)++__THRUST_SHELL_BOUNDARY__++(Bar)--
