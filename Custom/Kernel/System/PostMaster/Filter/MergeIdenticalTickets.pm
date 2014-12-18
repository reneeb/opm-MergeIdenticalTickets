# --
# Kernel/System/PostMaster/Filter/MergeIdenticalTickets.pm - sub part of PostMaster.pm
# Copyright (C) 2014 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::PostMaster::Filter::MergeIdenticalTickets;

use strict;
use warnings;

use List::Util qw(first);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{Debug} = $Param{Debug} || 0;

    # get needed objects
    for (qw(ConfigObject LogObject DBObject ParserObject TicketObject)) {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(JobConfig GetParam)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log( Priority => 'error', Message => "Need $_!" );
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

    if ( $Metrics{Body} && !$Metrics{HTMLBody} ) {
        $SearchCriteria{Body} = $Mail{Body}
    }

    my @TicketIDs = $Self->{TicketObject}->TicketSearch(
        %SearchCriteria,
        Result => 'ARRAY',
        UserID => 1,
    );

    return 1 if !@TicketIDs;

    my ($TicketID) = first { $_ ne $Param{TicketID} } reverse @TicketIDs;
    my ($HTMLFile) = first{ $_->{Filename} eq 'file-2' }@{ $Mail{Attachment} || [] };

    if ( $Metrics{HTMLBody} && $HTMLFile ) {
        my $Found = 0;

        POSSIBLETICKET:
        for my $PossibleTicket ( reverse @TicketIDs ) {
            next POSSIBLETICKET if $PossibleTicket eq $Param{TicketID};

            my %Article = $Self->{TicketObject}->ArticleFirstArticle(
                TicketID => $PossibleTicket,
                UserID   => 1,
            );

            my %AttachmentIndex = $Self->{TicketObject}->ArticleAttachmentIndex(
                ArticleID => $Article{ArticleID},
                UserID    => 1,
            );

            my ($FileID) = first { $AttachmentIndex{$_}->{Filename} eq 'file-2' }keys %AttachmentIndex;
            my %File     = $Self->{TicketObject}->ArticleAttachment(
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
        $Self->{TicketObject}->TicketMerge(
            MainTicketID  => $TicketID,
            MergeTicketID => $Param{TicketID},
            UserID        => 1,
        );
    }

    return 1;
}

1;
