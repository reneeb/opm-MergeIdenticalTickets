# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::MITRPSearch;

use strict;
use warnings;

our @ObjectDependencies = qw(
    Kernel::System::DB
);

=head1 NAME

Kernel::System::Ticket::MITRPSearch - ticket search lib

=head1 SYNOPSIS

All ticket search functions.

=over 4

=cut

=item new()

=cut

sub new {
    my ($Class, %Param) = @_;

    my $Self = bless {%Param}, $Class;

    return $Self;
}

=item Search()

To find tickets in your system.

    my @TicketIDs = $Object->Search(
        # article stuff (optional)
        Subject   => $Match,
        Delimiter => $Delimiter,
        From      => $FromMatch
        UserID    => $UserID,
    );

Returns:

    @TicketIDs = ( 1, 2, 3 );

=cut

sub Search {
    my ( $Self, %Param ) = @_;

    # check required params
    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID param for permission check!',
        );

        return;
    }

    # check required params
    if ( !$Param{Body} && !$Param{Subject} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need at least Body OR Subject param!',
        );

        return;
    }

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # create sql
    my $SQLSelect = q~
        SELECT DISTINCT st.id, st.tn
        FROM ticket st
            INNER JOIN queue sq ON sq.id = st.queue_id
            INNER JOIN article a ON st.id = a.ticket_id
        WHERE 1=1
    ~;

    my @Where;
    my @ViewableStateIDs = $Kernel::OM->Get('Kernel::System::State')->StateGetStatesByType(
        Type   => 'Viewable',
        Result => 'ID',
    );

    push @Where, " AND st.ticket_state_id IN ( " . (join ', ', sort {$a <=> $b} @ViewableStateIDs) . ") ";

    # article search criteria
    my @Bind;
    if ( $Param{From} ) {
        push @Bind, \$Param{From};
        push @Where, ' a.a_from LIKE ?';
    }

    if ( $Param{Subject} ) {
        push @Bind, \$Param{Subject};
        push @Where, ' a.a_subject LIKE ?';

        if ( $Param{Delimiter} ) {
            push @Bind, \$Param{Delimiter};
            push @Where, ' a.a_subject NOT LIKE ?';
        }
    }

    my %GroupList;

    # user groups
    if ( $Param{UserID} && $Param{UserID} != 1 ) {

        # get users groups
        %GroupList = $Kernel::OM->Get('Kernel::System::Group')->PermissionUserGet(
            UserID => $Param{UserID},
            Type   => $Param{Permission} || 'ro',
        );

        # return if we have no permissions
        return if !%GroupList;
    }

    # add group ids to sql string
    if (%GroupList) {

        my $GroupIDString = join ',', sort keys %GroupList;

        push @Where, " AND sq.group_id IN ($GroupIDString) ";
    }

    my $Where = !@Where ? '' : join ' AND ', @Where;
    $SQLSelect .= $Where;

    # database query
    my @TicketIDs;
    return if !$DBObject->Prepare(
        SQL   => $SQLSelect,
        Bind  => \@Bind,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @TicketIDs, $Row[0];
    }

    return @TicketIDs;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
