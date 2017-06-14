#!/bin/sh

#
# Copyright (c) 2015 EMC Corp.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $FreeBSD$
#

# Memory leak detector: run vmstat -m & -z in a loop.

export LANG=en_US.ISO8859-1
while getopts dmz flag; do
        case "$flag" in
        d) debug="-v debug=1" ;;
        m) optz=n ;;
        z) optm=n ;;
        *) echo "Usage $0 [-d] [-m] [-z]"
           return 1 ;;
        esac
done

pages=`sysctl -n vm.stats.vm.v_page_count`
start=`date '+%s'`
OIFS=$IFS
while true; do
	#          Type InUse MemUse
	[ -z "$optm" ] && vmstat -m | sed 1d |
	    sed 's/\(.* \)\([0-9][0-9]*\)  *\(.*\)K .*/\1:\2:\3/' |
	    while IFS=: read -r p1 p2 p3; do
		name=`echo $p1 | sed 's/^ *//;s/ *$//'`
		memuse=$p3
		[ "$memuse" -ne 0 ] && echo "vmstat -m $name,$memuse"
	done

	# ITEM                   SIZE  LIMIT     USED
	[ -z "$optz" ] && vmstat -z | sed "1,2d;/^$/d;s/: /, /" |
	    sed -E 's/[^[:print:]\r\t]/ /g' |
	    while read l; do
		IFS=','
		set $l
		[ $# -ne 8 ] &&
		    { echo "# args must be 8, but is $#in $l" 1>&2;
		        continue; }
		size=$2
		used=$4
		[ -z "$used" -o -z "$size" ] &&
		    { echo "used/size not set $l" 1>&2; continue; }
		tot=$((size * used / 1024))
		[ $tot -ne 0 ] &&
		   echo "vmstat -z $1,$tot"
	done

	r=`sysctl -n vm.stats.vm.v_wire_count`
	[ -n "$r" ] &&
	echo "vm.cnt.v_wire_count, \
	    $((r * 4))"
	r=`sysctl -n vm.stats.vm.v_free_count`
	[ -n "$r" ] &&
	echo "pages in use, \
	    $(((pages - r) * 4))"
	r=`sysctl -n vm.kmem_map_size`
	[ -n "$r" ] &&
	echo "kmem_map_size, $r"
	sleep 10
done | awk $debug -F, '
{
# Pairs of "name, value" are passed to this awk script.
	name=$1;
	size=$2;
	if (size > s[name]) {
		if (++n[name] > 60) {
			cmd="date '+%T'";
			cmd | getline t;
			close(cmd);
			printf "%s \"%s\" %'\''dK\r\n", t,
			    name, size;
			n[name] = 0;
		}
		s[name] = size;
		if (debug == 1 && n[name] > 1)
			printf "%s, size %d, count %d\r\n",
			    name, s[name], n[name]
	} else if (size < s[name] && n[name] > 0)
		n[name]--
}' | while read l; do
	d=$(((`date '+%s'` - start) / 86400))
	echo "$d $l"
done
# Note: the %'d is used to trigger a thousands-separator character.
