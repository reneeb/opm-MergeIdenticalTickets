# --
# Kernel/System/PostMaster/Filter/MergeIdenticalTicketsRegexPre.pm - sub part of PostMaster.pm
# Copyright (C) 2015 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::PostMaster::Filter::MergeIdenticalTicketsRegexPre;

use strict;
use warnings;

use List::Util qw(first);

our @ObjectDependencies = qw(
    Kernel::System::Ticket
    Kernel::System::Ticket::MITRPSearch
    Kernel::System::Log
    Kernel::System::Main
    Kernel::Config
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $SearchObject = $Kernel::OM->Get('Kernel::System::Ticket::MITRPSearch');

    $Self->{Debug} = $ConfigObject->Get('MergeIdenticalTickets::Debug');

    # check needed stuff
    for my $Needed (qw(JobConfig GetParam)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message => "Need $Needed!",
            );
            return;
        }
    }

    my $Regexes = $ConfigObject->Get('MergeIdenticalTickets::Regex') || {};

    if ( $Self->{Debug} ) {
        $LogObject->Log(
            Priority => 'notice',
            Message  => $MainObject->Dump( $Regexes ),
        );
    }

    return 1 if !$Regexes;

    my %Mail       = %{ $Param{GetParam} };
    my ($HTMLFile) = first{ $_->{Filename} eq 'file-2' }@{ $Mail{Attachment} || [] };

    KEY:
    for my $Key ( sort keys %{ $Regexes || {} } ) {

        my %SearchCriteria = ( StateType => 'Open' );

        my %RegexDetails = %{ $Regexes->{$Key} || {} };

        for my $RegexKey ( qw/Subject From/ ) {
            if ( defined $RegexDetails{$RegexKey} ) {
                my $Regex               = $RegexDetails{$RegexKey};
                my ($Found, $Delimiter) = $Mail{$RegexKey} =~ m{$Regex}ms;

                if ( $Self->{Debug} ) {
                    $LogObject->Log(
                        Priority => 'notice',
                        Message  => $MainObject->Dump( [ $Mail{$RegexKey}, $Regex, $Found, $Delimiter ] ),
                    );
                }

                next KEY if !defined $Found;

                if ( $Regex !~ m{ \\A }xms ) {
                    $Found = '%' . $Found;
                }

                my $Position = 0;
                if ( $Regex !~ m{ \\z }xms ) {
                    $Found .= '%';
                    $Position = 1;
                }

                $SearchCriteria{$RegexKey} = $Found;

                if ( $Delimiter ) {
                    my $Value = $Found;
                    substr $Value, (length( $Value ) - $Position), 0, $Delimiter;
                    $SearchCriteria{Delimiter} = $Value;
                }
            }
        }

        if ( $Self->{Debug} ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => $MainObject->Dump( \%SearchCriteria ),
            );
        }

        my @TicketIDs = $SearchObject->Search(
            %SearchCriteria,
            UserID => 1,
        );

        if ( $Self->{Debug} ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => $MainObject->Dump( \@TicketIDs ),
            );
        }

        next KEY if !@TicketIDs;

        my ($TicketID) = (reverse sort @TicketIDs)[0];

        if ( $RegexDetails{Body} ) {
            my $TextToCheck = $HTMLFile ? $HTMLFile->{Content} : $Mail{Body};
            my ($BodyMatch) = $TextToCheck =~ m{$RegexDetails{Body}}ms;

            next KEY if !$BodyMatch;

            my $Found = 0;

            POSSIBLETICKET:
            for my $PossibleTicket ( reverse @TicketIDs ) {
                my %Article = $TicketObject->ArticleFirstArticle(
                    TicketID => $PossibleTicket,
                    UserID   => 1,
                );

                my %AttachmentIndex = $TicketObject->ArticleAttachmentIndex(
                    ArticleID => $Article{ArticleID},
                    UserID    => 1,
                );

                my ($FileID) = first { $AttachmentIndex{$_}->{Filename} eq 'file-2' }keys %AttachmentIndex;
                my %File     = $TicketObject->ArticleAttachment(
                    FileID    => $FileID,
                    ArticleID => $Article{ArticleID},
                    UserID    => 1,
                );

                if ( $File{Content} =~ m{\Q$BodyMatch\E}ms ) {
                    $Found++;
                    $TicketID = $PossibleTicket;
                    last POSSIBLETICKET;
                }

                $TicketID = undef if !$Found;
            }
        }

        if ( $TicketID ) {
            my $TicketNumber = $TicketObject->TicketNumberLookup(
                TicketID => $TicketID,
                UserID   => 1,
            );

            $Param{GetParam}->{Subject} = $TicketObject->TicketSubjectBuild(
                TicketNumber => $TicketNumber,
                Subject      => $Mail{Subject},
                Type         => 'New',
                NoCleanUp    => 1,
            );

            last KEY;
        }
    }

    return 1;
}

1;
