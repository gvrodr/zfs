#!/bin/ksh -p
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#

#
# Copyright 2017, loli10K <ezomori.nozomu@gmail.com>. All rights reserved.
#

. $STF_SUITE/include/libtest.shlib
. $STF_SUITE/tests/functional/cli_root/zfs_set/zfs_set_common.kshlib
. $STF_SUITE/tests/functional/zvol/zvol_common.shlib

#
# DESCRIPTION:
# Verify that ZFS volume property "snapdev" works as intended.
#
# STRATEGY:
# 1. Verify "snapdev" property does not accept invalid values
# 2. Verify "snapdev" adds and removes device nodes when updated
# 3. Verify "snapdev" is inherited correctly
#

verify_runnable "global"

function cleanup
{
	datasetexists $VOLFS && log_must zfs destroy -r $VOLFS
	datasetexists $ZVOL && log_must zfs destroy -r $ZVOL
	log_must zfs inherit snapdev $TESTPOOL
	block_device_wait
}

#
# Verify $device exists and is a block device
#
function blockdev_exists # device
{
	typeset device="$1"

	if [[ ! -b "$device" ]]; then
		log_fail "$device does not exist as a block device"
	fi
}

#
# Verify $device does not exist
#
function check_missing # device
{
	typeset device="$1"

	if [[ -e "$device" ]]; then
		log_fail "$device exists when not expected"
	fi
}

#
# Verify $property on $dataset is inherited by $parent and is set to $value
#
function verify_inherited # property value dataset parent
{
	typeset property="$1"
	typeset value="$2"
	typeset dataset="$3"
	typeset parent="$4"

	typeset val=$(get_prop "$property" "$dataset")
	typeset src=$(get_source "$property" "$dataset")
	if [[ "$val" != "$value" || "$src" != "inherited from $parent" ]]
	then
		log_fail "Dataset $dataset did not inherit $property properly:"\
		    "expected=$value, value=$val, source=$src."
	fi

}

log_assert "Verify that ZFS volume property 'snapdev' works as expected."
log_onexit cleanup

VOLFS="$TESTPOOL/volfs"
ZVOL="$TESTPOOL/vol"
SNAP="$ZVOL@snap"
SNAPDEV="${ZVOL_DEVDIR}/$SNAP"
SUBZVOL="$VOLFS/subvol"
SUBSNAP="$SUBZVOL@snap"
SUBSNAPDEV="${ZVOL_DEVDIR}/$SUBSNAP"

log_must zfs create -o mountpoint=none $VOLFS
log_must zfs create -V $VOLSIZE -s $ZVOL
log_must zfs create -V $VOLSIZE -s $SUBZVOL

# 1. Verify "snapdev" property does not accept invalid values
typeset badvals=("off" "on" "1" "nope" "-")
for badval in ${badvals[@]}
do
	log_mustnot zfs set snapdev="$badval" $ZVOL
done

# 2. Verify "snapdev" adds and removes device nodes when updated
# 2.1 First create a snapshot then change snapdev property
log_must zfs snapshot $SNAP
log_must zfs set snapdev=visible $ZVOL
block_device_wait
blockdev_exists $SNAPDEV
log_must zfs set snapdev=hidden $ZVOL
block_device_wait
check_missing $SNAPDEV
log_must zfs destroy $SNAP
# 2.2 First set snapdev property then create a snapshot
log_must zfs set snapdev=visible $ZVOL
log_must zfs snapshot $SNAP
block_device_wait
blockdev_exists $SNAPDEV
log_must zfs destroy $SNAP
block_device_wait
check_missing $SNAPDEV

# 3. Verify "snapdev" is inherited correctly
# 3.1 Check snapdev=visible case
log_must zfs snapshot $SNAP
log_must zfs inherit snapdev $ZVOL
log_must zfs set snapdev=visible $TESTPOOL
verify_inherited 'snapdev' 'visible' $ZVOL $TESTPOOL
block_device_wait
blockdev_exists $SNAPDEV
# 3.2 Check snapdev=hidden case
log_must zfs set snapdev=hidden $TESTPOOL
verify_inherited 'snapdev' 'hidden' $ZVOL $TESTPOOL
block_device_wait
check_missing $SNAPDEV
# 3.3 Check inheritance on multiple levels
log_must zfs snapshot $SUBSNAP
log_must zfs inherit snapdev $SUBZVOL
log_must zfs set snapdev=hidden $VOLFS
log_must zfs set snapdev=visible $TESTPOOL
verify_inherited 'snapdev' 'hidden' $SUBZVOL $VOLFS
block_device_wait
check_missing $SUBSNAPDEV
blockdev_exists $SNAPDEV

log_pass "ZFS volume property 'snapdev' works as expected"