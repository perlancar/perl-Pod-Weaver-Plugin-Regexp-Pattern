package Pod::Weaver::Plugin::Regexp::Pattern;

# DATE
# VERSION

use 5.010001;
use Moose;
with 'Pod::Weaver::Role::AddTextToSection';
with 'Pod::Weaver::Role::Section';

#has include_module => (is=>'rw');
#has exclude_module => (is=>'rw');

use Data::Dmp;

sub _md2pod {
    require Markdown::To::POD;

    my ($self, $md) = @_;
    my $pod = Markdown::To::POD::markdown_to_pod($md);
    # make sure we add a couple of blank lines in the end
    $pod =~ s/\s+\z//s;
    $pod . "\n\n\n";
}

sub _process_module {
    no strict 'refs';

    my ($self, $document, $input, $package) = @_;

    my $filename = $input->{filename};

    # XXX handle dynamically generated module (if there is such thing in the
    # future)
    local @INC = ("lib", @INC);

    {
        my $package_pm = $package;
        $package_pm =~ s!::!/!g;
        $package_pm .= ".pm";
        require $package_pm;
    }

    (my $rp_package = $package) =~ s/\ARegexp::Pattern:://;

    my $var = \%{"$package\::RE"};
    my @patnames = sort keys %$var;

    # add Synopsis section
    {
        my @pod;
        last unless @patnames;
        push @pod, " use Regexp::Pattern; # exports re()\n";
        push @pod, " my \$re = re(", dmp("$rp_package\::$patnames[0]"), ");\n";
        push @pod, "\n";

        $self->add_text_to_section(
            $document, join("", @pod), 'SYNOPSIS',
            {
                after_section => ['VERSION', 'NAME'],
                before_section => 'DESCRIPTION',
                ignore => 1,
            });
    }

    # add Description section
    {
        my @pod;

        # blurb about Regexp::Pattern
        push @pod, "L<Regexp::Pattern> is a convention for organizing reusable regex patterns.\n\n";

        $self->add_text_to_section(
            $document, join("", @pod), 'DESCRIPTION',
            {
                after_section => ['SYNOPSIS'],
                ignore => 1,
            });
    }

    # add Patterns section
    {
        my @pod;

        push @pod, "=over\n\n";
        for my $patname (@patnames) {
            my $patspec = $var->{$patname};
            push @pod, "=item * $patname\n\n";
            if (defined $patspec->{summary}) {
                require String::PodQuote;
                push @pod, String::PodQuote::pod_quote($patspec->{summary}), ".\n\n";
            }
            push @pod, $self->_md2pod($patspec->{description})
                if $patspec->{description};

            if ($patspec->{gen}) {
                push @pod, "This is a dynamic pattern which will be generated on-demand.\n\n";
                if ($patspec->{gen_args} && keys(%{$patspec->{gen_args}})) {
                    push @pod, "The following arguments are available to customize the generated pattern:\n\n";
                    push @pod, "=over\n\n";
                    for my $argname (sort keys %{ $patspec->{gen_args} }) { # XXX sort by position, then name
                        my $argspec = $patspec->{gen_args}{$argname};
                        push @pod, "=item * $argname\n\n";
                        if (defined $argspec->{summary}) {
                            require String::PodQuote;
                            push @pod, String::PodQuote::pod_quote($argspec->{summary}), ".\n\n";
                        }
                        push @pod, $self->_md2pod($argspec->{description})
                            if $argspec->{description};
                    }
                    push @pod, "=back\n\n";
                }
                push @pod, "\n\n";
            }

          RENDER_EXAMPLES:
            {
                last unless $patspec->{examples};
                my @eg;
                for my $eg (@{ $patspec->{examples} }) {
                    next unless $eg->{doc} // 1;
                    push @eg, $eg;
                }
                last unless @eg;
                push @pod, "Examples:\n\n";
                for my $eg (@eg) {
                    if (defined $eg->{summary}) {
                        require String::PodQuote;
                        push @pod, String::PodQuote::pod_quote($eg->{summary}), ".\n\n";
                    }

                    push @pod, " ", dmp($eg->{str}), " =~ re(", dmp("$rp_package\::$patname"), ($eg->{gen_args} ? ", ".dmp($eg->{gen_args}) : ""), "); ";
                    if (ref $eg->{matches} eq 'ARRAY') {
                        if (@{ $eg->{matches} }) {
                            push @pod, "# matches, ",
                                join(", ", map {
                                    "\$".($_+1)."=".dmp($eg->{matches}[$_])}
                                     0..$#{$eg->{matches}});
                        } else {
                            push @pod, " # doesn't match";
                        }
                    } elsif (ref $eg->{matches} eq 'HASH') {
                        if (keys %{ $eg->{matches} }) {
                            push @pod, "# matches, ",
                                join(", ", map {
                                    "\$+{" . dmp($_) . "}=" . dmp($eg->{matches}{$_})}
                                     sort keys %{$eg->{matches}});
                        } else {
                            push @pod, " # doesn't match";
                        }
                    } else {
                        if ($eg->{matches}) {
                            push @pod, " # matches";
                        } else {
                            push @pod, " # doesn't match";
                        }
                    }
                    push @pod, "\n\n";
                }
            }
        }
        push @pod, "=back\n\n";

        $self->add_text_to_section(
            $document, join("", @pod), 'PATTERNS',
            {
                after_section => ['DESCRIPTION'],
            });
    }

    # mention some modules in See Also section
    {
        my @pod = (
            "L<Regexp::Pattern>\n\n",
            "Some utilities related to Regexp::Pattern: L<App::RegexpPatternUtils>, L<rpgrep> from L<App::rpgrep>.\n\n",
        );
        $self->add_text_to_section(
            $document, join('', @pod), 'SEE ALSO',
        );
    }

    $self->log(["Generated POD for '%s'", $filename]);
}

sub weave_section {
    my ($self, $document, $input) = @_;

    my $filename = $input->{filename};

    my $package;
    if ($filename =~ m!^lib/(Regexp/Pattern/.+)\.pm$!) {
        $package = $1;
        $package =~ s!/!::!g;
        #if ($self->include_module && @{ $self->include_module }) {
        #    return unless grep {"Regexp::Pattern::$_" eq $package} @{ $self->include_module };
        #}
        #if ($self->exclude_module && @{ $self->exclude_module }) {
        #    return if grep {"Regexp::Pattern::$_" eq $package} @{ $self->exclude_module };
        #}
        $self->_process_module($document, $input, $package);
    }
}

1;
# ABSTRACT: Plugin to use when building Regexp::Pattern::* distribution

=for Pod::Coverage .*

=head1 SYNOPSIS

In your F<weaver.ini>:

 [-Regexp::Pattern]


=head1 DESCRIPTION

This plugin is to be used when building C<Regexp::Pattern::*> distribution.
Currently it does the following:

=over

=item * Add a Synopsis section (if doesn't already exist) containing a few examples on how to use the module

=item * Add a description about Regexp::Pattern in the Description section

=item * Add a Patterns section containing list of patterns contained in the module

=item * Mention some modules in the See Also section, including Regexp::Pattern

=back


=head1 CONFIGURATION


=head1 SEE ALSO

L<Regexp::Pattern>

L<Dist::Zilla::Plugin::Regexp::Pattern>
