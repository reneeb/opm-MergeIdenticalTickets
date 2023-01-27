# --
# Copyright (C) 2014 - 2023 Perl-Services.de, https://www.perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::PostMaster::Filter::MergeIdenticalTickets;

use strict;
use warnings;

use Kernel::System::EmailParser;

use List::Util qw(first);

our @ObjectDependencies = qw(
    Kernel::Config
    Kernel::System::Ticket::Article
    Kernel::System::Log
    Kernel::System::Main
    Kernel::System::Ticket::MITRPSearch
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    $Self->{Debug} = $Param{Debug} || 0;

    # get communication log object and MessageID
    $Self->{CommunicationLogObject} = $Param{CommunicationLogObject} || die "Got no CommunicationLogObject!";

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
    my $MainObject    = $Kernel::OM->Get('Kernel::System::Main');
    my $ConfigObject  = $Kernel::OM->Get('Kernel::Config');
    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
    my $SearchObject  = $Kernel::OM->Get('Kernel::System::Ticket::MITRPSearch');

    my $UserID = $ConfigObject->Get('PostmasterUserID') || 1;

    $Self->{CommunicationLogObject}->ObjectLog(
        ObjectLogType => 'Message',
        Priority      => 'Debug',
        Key           => __PACKAGE__,
        Value         => "Starting filter " . __PACKAGE__,
    );

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
        $SearchCriteria{From} = $Mail{From};
    }

    if ( $Metrics{PlainFrom} ) {
        my $ParserObject = Kernel::System::EmailParser->new(
            Mode => 'Standalone',
        );

        $SearchCriteria{From} = $ParserObject->GetEmailAddress(
            Email => $Mail{From},
        );
    }

    if ( $Metrics{Subject} ) {
        $SearchCriteria{Subject} = $Mail{Subject}
    }

    my ($HTMLFile) = first{ $_->{Filename} eq 'file-2' }@{ $Mail{Attachment} || [] };
    if ( $Metrics{Body} && ( !$Metrics{HTMLBody} || !$HTMLFile ) ) {
        $SearchCriteria{Body} = $Mail{Body}
    }

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my @TicketIDs    = $SearchObject->Search(
        %SearchCriteria,
        UserID => $UserID,
        Exact  => 1,
    );

    return 1 if !@TicketIDs;

    my ($TicketID) = first { $_ ne $Param{TicketID} } reverse sort @TicketIDs;

    if ( $Metrics{HTMLBody} && $HTMLFile ) {
        my $Found = 0;

        POSSIBLETICKET:
        for my $PossibleTicket ( reverse @TicketIDs ) {
            next POSSIBLETICKET if $PossibleTicket eq $Param{TicketID};

            my ($ArticleData) = $ArticleObject->ArticleList(
                TicketID => $PossibleTicket,
                UserID   => $UserID,
                First    => 1,
            );

            my $BackendObject = $ArticleObject->BackendForArticle(
                ArticleID => $ArticleData->{ArticleID},
                TicketID  => $PossibleTicket,
            );

            next POSSIBLETICKET if !$BackendObject->can('ArticleAttachmentIndex');

            my %AttachmentIndex = $BackendObject->ArticleAttachmentIndex(
                ArticleID => $ArticleData->{ArticleID},
            );

            my ($FileID) = first { $AttachmentIndex{$_}->{Filename} eq 'file-2' }keys %AttachmentIndex;
            my %File     = $BackendObject->ArticleAttachment(
                FileID    => $FileID,
                ArticleID => $ArticleData->{ArticleID},
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
        $Self->{CommunicationLogObject}->ObjectLog(
            ObjectLogType => 'Message',
            Priority      => 'Debug',
            Key           => __PACKAGE__,
            Value         => "Merge with ticket $TicketID",
        );

        $TicketObject->TicketMerge(
            MainTicketID  => $TicketID,
            MergeTicketID => $Param{TicketID},
            UserID        => $UserID,
        );
    }

    return 1;
}

1;
