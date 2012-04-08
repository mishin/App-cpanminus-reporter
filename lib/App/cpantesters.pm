package App::cpantesters;

use warnings;
use strict;

our $VERSION = '0.01';

use Carp ();
use File::Spec;
use File::HomeDir;
use Test::Reporter 1.54;
use CPAN::Testers::Common::Client;
use Parse::CPAN::Meta;
use CPAN::Meta::Converter;

sub new {
  my ($class, %params) = @_;
  my $self = bless {}, $class;

  $self->cpanm_dir(
          $params{cpanm_dir}
       || File::Spec->catdir( File::HomeDir->my_home, '.cpanm' )
  );

  $self->build_logfile(
          $params{build_logfile}
      ||  File::Spec->catfile( $self->cpanm_dir, 'build.log' )
  );

  return $self;
}

sub cpanm_dir {
  my ($self, $dir) = @_;
  $self->{_cpanm_dir} = $dir if $dir;
  return $self->{_cpanm_dir};
}

sub build_logfile {
  my ($self, $file) = @_;
  $self->{_build_logfile} = $file if $file;
  return $self->{_build_logfile};
}


sub run {
  my $self = shift;

  my $logfile = $self->build_logfile;
  open my $fh, '<', $logfile
    or Carp::croak "error opening build log file '$logfile' for reading: $!";

  my $parser;

  $parser = sub {
    my ($dist, $resource) = @_;
    my @test_output = ();
    my $recording = 0;
    my $str = '';
    my $fetched;

    while (<$fh>) {
        if ( /^Fetching (\S+)/ ) {
            $fetched = $1;
            $resource = $fetched unless $resource;
        }
        elsif ( /^Entering (\S+)/ ) {
            my $dep = $1;
            Carp::croak 'Parsing error. This should not happen. Please send us a report!' if $recording;
            Carp::croak "Parsing error. Found '$dep' without fetching first." unless $resource;
            print "entering $dep, $fetched\n";
            $parser->($dep, $fetched);
            print "left $dep, $fetched\n";
            next;
        }
        elsif ( $dist and /^Building and testing $dist/) {
            print "recording $dist\n";
            $recording = 1;
        }

        push @test_output, $_ if $recording;
       
        if ( $recording and ( /^Result: (PASS|NA|FAIL|UNKNOWN)/ or /^-> (FAIL) Installing/ ) ) {
            my $result = $1;
            warn "sending: ($resource, $dist, $result)\n";
            my $report = $self->make_report($resource, $dist, $result, @test_output);
            return;
        }
    }
  };

  $parser->();

  close $fh;
  return;
}


sub make_report {
    my ($self, $resource, $dist, $result, @test_output) = @_;

    # TODO: this should definitely be stricter
    if ( $resource =~ m{cpan.+/id/.+/([A-Z]+)/($dist\..+)$} ) {
        $resource = "cpan:///distfile/$1/$2";
    }
    else {
        Carp::croak "error parsing '$resource' for '$dist'. Please send us a report!";
    }

    eval { require App::cpanminus };
    my $cpanm = $@ ? 'unknown cpanm' : "cpanm $App::cpanminus::VERSION";

    my $meta = $self->get_meta_for( $dist );
    my $client = CPAN::Testers::Common::Client->new(
          resource    => $resource,
          via         => "App::cpantesters $VERSION ($cpanm)",
          grade       => $result,
          test_output => join( '', @test_output ),
          prereqs     => $meta->{prereqs},
    );

    my $reporter = Test::Reporter->new(
        transport      => 'File',
        transport_args => [ '/tmp/reporter' ],
        grade          => $client->grade,
        distribution   => $dist,
        from           => 'whoever@wherever.net (Whoever Wherever)',
        comments       => $client->email,
        via            => $client->via,
    );
    $reporter->send() || die $reporter->errstr();
}

sub get_meta_for {
    my ($self, $dist) = @_;
    my $distdir = File::Spec->catdir( $self->cpanm_dir, 'latest-build', $dist );

    foreach my $meta_file ( qw( META.json META.yml META.yaml ) ) {
        my $meta_path = File::Spec->catfile( $distdir, $meta_file );
        if (-e $meta_path) {
            my $meta = eval { Parse::CPAN::Meta->load_file( $meta_path ) };
            next if $@;

            if ($meta->{'meta-spec'}{version} < 2) {
                $meta = CPAN::Meta::Converter->new( $meta )->convert( version => 2 );
            }
            return $meta;
        }
    }
    return undef;
}

#sub send_report {
#    my $tr = Test::Reporter->new;
#    $tr->grade( $grade );
#    $tr->distribution( $dist );
#    $tr->distfile( );
#    
#}


42;
__END__

=head1 NAME

App::cpantesters - [One line description of module's purpose here]


=head1 SYNOPSIS

    use App::cpantesters;

  
=head1 DESCRIPTION


=head1 INTERFACE 

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=over 4

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
App::cpantesters requires no configuration files or environment variables.


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
C<bug-app-cpantesters@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Breno G. de Oliveira  C<< <garu@cpan.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2012, Breno G. de Oliveira C<< <garu@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.