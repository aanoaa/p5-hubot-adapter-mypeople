package Hubot::Adapter::Mypeople;
use Moose;
use namespace::autoclean;

extends 'Hubot::Adapter';

use AnyEvent::HTTPD;
use AnyEvent::HTTP::ScopedClient;
use JSON::XS;

use Hubot::Message;

has httpd => (
    is         => 'ro',
    lazy_build => 1,
);

has apikey => (
    is  => 'rw',
    isa => 'Str',
);

has _shutdown => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

sub _build_httpd { AnyEvent::HTTPD->new(port => $ENV{HUBOT_MYPEOPLE_PORT} || 8080) }

sub send {
    my ( $self, $user, @strings ) = @_;

    my $from = $user->{from};
    my $client = $self->robot->http("https://apis.daum.net/mypeople/$from/send.json?apikey=" . $self->apikey);
    $client->header('Accept', 'application/json');
    $client->post({
        $from . 'Id' => $user->{room},
        content      => join("\n", @strings)
    }, sub {
        my ($body, $hdr) = @_;
        print $body if $ENV{DEBUG};
        $self->httpd->stop if $self->_shutdown;
    });
}

sub reply {
    my ( $self, $user, @strings ) = @_;

    @strings = map { $user->{name} . ": $_" } @strings;
    $self->send( $user, @strings );
}

sub run {
    my $self = shift;

    unless ($ENV{HUBOT_MYPEOPLE_APIKEY}) {
        print STDERR "HUBOT_MYPEOPLE_APIKEY is not defined, try: export HUBOT_MYPEOPLE_APIKEY='yourapikey'";
        exit;
    }

    $self->apikey($ENV{HUBOT_MYPEOPLE_APIKEY});

    my $httpd = $self->httpd;

    $httpd->reg_cb(
        '/' => sub {
            my ($httpd, $req) = @_;

            my $action  = $req->parm('action');
            my $buddyId = $req->parm('buddyId');
            my $groupId = $req->parm('groupId');
            my $content = $req->parm('content');

            $req->respond(
                {
                    content => [
                        'text/plain',
                        "hello, world"
                    ]
                }
            );

            return unless $action =~ /^sendFrom/; # sendFromMessage|sendFromGroup

            ## '-'] hmm.. createUser takes callback; bad naming
            $self->createUser(
                $buddyId,
                $groupId,
                sub {
                    my $user = shift;

                    $self->receive(
                        Hubot::TextMessage->new(
                            user => $user,
                            text => $content,
                        )
                    );
                }
            );
        }
    );

    my $port = $ENV{HUBOT_MYPEOPLE_PORT} || 8080;
    print __PACKAGE__ . " Accepting connection at http://0:$port\n";

    $self->emit('connected');
    $httpd->run;
}

sub createUser {
    my ( $self, $buddyId, $groupId, $cb ) = @_;

    my $user = $self->userForId($buddyId, {
        room => $groupId || $buddyId,
        from => $groupId ? 'group' : 'buddy',
    });

    return $cb->($user) if $user->{id} ne $user->{name};

    my $client = $self->robot->http("https://apis.daum.net/mypeople/profile/buddy.json?apikey=" . $self->apikey);

    $client->header('Accept', 'application/json')
        ->post({ buddyId => $buddyId },
            sub {
                my ($body, $hdr) = @_;

                return if ( !$body || $hdr->{Status} !~ /^2/ ); # debug log?

                my $json = decode_json($body);
                $user->{name} = $json->{buddys}[0]{name};

                $cb->($user, $json);
            }
        );
}

sub close { shift->_shutdown(1) }

__PACKAGE__->meta->make_immutable;

1;
