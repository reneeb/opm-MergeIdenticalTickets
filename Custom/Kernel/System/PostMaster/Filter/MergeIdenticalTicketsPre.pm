# --
# Kernel/System/PostMaster/Filter/MergeIdenticalTicketsPre.pm - sub part of PostMaster.pm
# Copyright (C) 2015 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::PostMaster::Filter::MergeIdenticalTicketsPre;

use strict;
use warnings;

use List::Util qw(first);

our @ObjectDependencies = qw(
    Kernel::System::Ticket
    Kernel::System::Log
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{Debug} = $Param{Debug} || 0;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

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

    # get config options
    my %Config;
    my %Metrics;

    if ( $Param{JobConfig} && ref $Param{JobConfig} eq 'HASH' ) {
        %Config  = %{ $Param{JobConfig} };
        %Metrics = %{ $Param{JobConfig}->{Metric} || {} };
    }

    return 1 if !%Config;
    return 1 if !%Metrics;

    my %Mail = %{ $Param{GetParam} };

    my %SearchCriteria = ( StateType => 'Open' );
    if ( $Metrics{From} ) {
        $SearchCriteria{From} = $Mail{From}
    }

    if ( $Metrics{Subject} ) {
        $SearchCriteria{Subject} = $Mail{Subject}
    }

    my ($HTMLFile) = first{ $_->{Filename} eq 'file-2' }@{ $Mail{Attachment} || [] };
    if ( $Metrics{Body} && ( !$Metrics{HTMLBody} || !$HTMLFile ) ) {
        $SearchCriteria{Body} = $Mail{Body}
    }

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my @TicketIDs    = $TicketObject->TicketSearch(
        %SearchCriteria,
        Result => 'ARRAY',
        UserID => 1,
    );

    return 1 if !@TicketIDs;

    my ($TicketID) = (reverse sort @TicketIDs)[0];

    if ( $Metrics{HTMLBody} && $HTMLFile ) {
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

            if ( $File{Content} eq $HTMLFile->{Content} ) {
                $Found++;
                $TicketID = $PossibleTicket;
                last POSSIBLETICKET;
            }
        }

        $TicketID = undef if !$Found;
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
    }

    return 1;
}

1;
