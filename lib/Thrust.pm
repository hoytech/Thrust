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

=head1 SEE ALSO

L<The Thrust perl module github repo|https://github.com/hoytech/Thrust>

L<The Thrust project|https://github.com/breach/thrust>

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
