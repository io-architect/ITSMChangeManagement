# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2020 Rother OSS GmbH, https://otobo.de/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::System::ITSMChange::ITSMWorkOrder::Event::WorkOrderActualTimesSet;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DateTime',
    'Kernel::System::ITSMChange::ITSMStateMachine',
    'Kernel::System::ITSMChange::ITSMWorkOrder',
    'Kernel::System::Log',
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

    # check needed stuff
    for my $Needed (qw(Data Event Config UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # handle WorkOrderUpdate event
    if ( $Param{Event} eq 'WorkOrderUpdatePost' ) {

        # get WorkOrder
        my $WorkOrder = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderGet(
            WorkOrderID => $Param{Data}->{WorkOrderID},
            UserID      => $Param{UserID},
        );

        # check error
        return if !$WorkOrder;

        # get actual start time from workorder
        my $ActualStartTime = $WorkOrder->{ActualStartTime};

        # get configured workorder states when to set actual start time
        my $ConfiguredWorkOrderStartStates
            = $Kernel::OM->Get('Kernel::Config')->Get('ITSMWorkOrder::ActualStartTimeSet::States');

        # convert into hash for easier lookup
        my %ActualStartTimeSetStates = map { $_ => 1 } @{$ConfiguredWorkOrderStartStates};

        # get current time stamp
        my $CurrentTimeStamp = $Kernel::OM->Create('Kernel::System::DateTime')->ToString();

        # check if ActualStartTime is empty,
        # and WorkOrderState is in an ActualStartTimeSetState
        if ( !$ActualStartTime && $ActualStartTimeSetStates{ $WorkOrder->{WorkOrderState} } ) {

            # set the actual start time
            my $Success = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderUpdate(
                WorkOrderID     => $Param{Data}->{WorkOrderID},
                ActualStartTime => $CurrentTimeStamp,
                UserID          => $Param{UserID},
            );

            # check error
            if ( !$Success ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message =>
                        "Could not set ActualStartTime for WorkOrderID '$Param{Data}->{WorkOrderID}'!",
                );
                return;
            }

            # remember the just set actual start time
            $ActualStartTime = $CurrentTimeStamp;
        }

        # check if the ActualEndTime is empty
        # and the current workorder state is an end state
        if ( !$WorkOrder->{ActualEndTime} ) {

            # get the possible next state ids
            my $NextStateIDsRef = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMStateMachine')->StateTransitionGet(
                StateID => $WorkOrder->{WorkOrderStateID},
                Class   => 'ITSM::ChangeManagement::WorkOrder::State',
            ) || [];

            # if there is only one next state, which is also 0,
            # which means that this is an end state
            if ( ( scalar @{$NextStateIDsRef} == 1 ) && ( !$NextStateIDsRef->[0] ) ) {

                # if no actual start time is set, use the current time
                if ( !$ActualStartTime ) {
                    $ActualStartTime = $CurrentTimeStamp;
                }

                # increase the current time stamp by one second to avoid the case that
                # actual start and end times are the same
                my $ActualEndTime = $Kernel::OM->Create(
                    'Kernel::System::DateTime',
                    ObjectParams => {
                        String => $CurrentTimeStamp,
                    },
                );
                $ActualEndTime->Add(
                    Seconds => 1,
                );
                $ActualEndTime = $ActualEndTime->ToString();

                # set the actual end time,
                # and if the actual start time was not set, set it also
                my $Success = $Kernel::OM->Get('Kernel::System::ITSMChange::ITSMWorkOrder')->WorkOrderUpdate(
                    WorkOrderID     => $Param{Data}->{WorkOrderID},
                    ActualStartTime => $ActualStartTime,
                    ActualEndTime   => $ActualEndTime,
                    UserID          => $Param{UserID},
                );

                # check error
                if ( !$Success ) {
                    $Kernel::OM->Get('Kernel::System::Log')->Log(
                        Priority => 'error',
                        Message =>
                            "Could not set ActualStartTime for WorkOrderID '$Param{Data}->{WorkOrderID}'!",
                    );
                    return;
                }
            }
        }
    }

    # error
    else {

        # an unknown event
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "$Param{Event} is an unknown event for this eventhandler!",
        );

        return;
    }

    return 1;
}

1;