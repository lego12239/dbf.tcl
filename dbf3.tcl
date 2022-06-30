# Copyright (C) 2022 Oleg Nemanov <lego12239@yandex.ru>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

package provide dbf3 0.1

# https://www.clicketyclick.dk/databases/xbase/format/index.html
# http://www.independent-software.com/dbase-dbf-dbt-file-format.html

namespace eval dbf::3 {
proc _setup_handlers {_dbh} {
	upvar $_dbh dbh

	dict set dbh hdl _fdesc_set ::dbf::3::_fdesc_set
	dict set dbh hdl _header_read ::dbf::3::_header_read
	dict set dbh hdl _header_write ::dbf::3::_header_write
	dict set dbh hdl _rec_read ::dbf::3::_rec_read
	dict set dbh hdl _rec_append ::dbf::3::_rec_append
	dict set dbh hdl _rec_write ::dbf::3::_rec_write
	dict set dbh hdl _rec_rm ::dbf::3::_rec_rm
}

proc _fdesc_set {_dbh fdesc} {
	upvar $_dbh dbh

	for {set i 0} {$i < [llength $fdesc]} {incr i} {
		set f1desc [lindex $fdesc $i]
		switch -- [dict get $f1desc type] {
		D {
			dict set f1desc size 8
		}
		L {
			dict set f1desc size 1
		}
		}
		lset fdesc $i $f1desc
	}

	dict set dbh hdr fdesc $fdesc
}

proc _header_read {_dbh} {
	upvar $_dbh dbh

	set fh [dict get $dbh fh]
	seek $fh 1 start

	# Last update date
	set data [read $fh 1]
	if {[string length $data] != 1} {
		error "File end too early: can't read header: can't read a date year"
	}
	binary scan $data c dyear
	incr dyear 1900

	set data [read $fh 1]
	if {[string length $data] != 1} {
		error "File end too early: can't read header: can't read a date month"
	}
	binary scan $data c dmonth

	set data [read $fh 1]
	if {[string length $data] != 1} {
		error "File end too early: can't read header: can't read a date day"
	}
	binary scan $data c dday

	dict set dbh hdr lastupd_date [clock scan [format "%04d-%02d-%02d" $dyear $dmonth $dday] -format "%Y-%m-%d" -timezone ":UTC"]

	# Number of records
	set data [read $fh 4]
	if {[string length $data] != 4} {
		error "File end too early: can't read header: can't read a records count"
	}
	binary scan $data i num

	dict set dbh hdr rec_cnt $num

	# Size of header
	set data [read $fh 2]
	if {[string length $data] != 2} {
		error "File end too early: can't read header: can't read a header size"
	}
	binary scan $data s num

	dict set dbh hdr hdr_size $num

	# Size of record
	set data [read $fh 2]
	if {[string length $data] != 2} {
		error "File end too early: can't read header: can't read a record size"
	}
	binary scan $data s num

	dict set dbh hdr rec_size $num

	_fdesc_read dbh
}

proc _fdesc_read {_dbh} {
	upvar $_dbh dbh
	set idx 0
	set fdesc [list]

	set fh [dict get $dbh fh]
	seek $fh 32 start

	while {[set data [read $fh 1]] ne "\x0d"} {
		set f1desc [dict create]
		# Field name
		set data "$data[read $fh 10]"
		if {[string length $data] != 11} {
			error [string cat "File end too early: can't read header: "\
			  "can't read a field name for $idx"]
		}
		dict set f1desc name [string range $data 0 [string first \x00 $data]-1]

		# Field type
		set data [read $fh 1]
		if {[string length $data] != 1} {
			error [string cat "File end too early: can't read header: "\
			  "can't read a field type for $idx"]
		}
		dict set f1desc type $data

		# Field size
		seek $fh 4 current
		set data [read $fh 1]
		if {[string length $data] != 1} {
			error [string cat "File end too early: can't read header: "\
			  "can't read a field size for $idx"]
		}
		binary scan $data c num
		dict set f1desc size $num

		lappend fdesc $f1desc

		incr idx
		seek $fh [expr {32 + $idx*32}] start
	}

	dict set dbh hdr fdesc $fdesc
}

proc _header_write {_dbh} {
	upvar $_dbh dbh

	set fh [dict get $dbh fh]
	seek $fh 1 start

	# Last update date
	set data [clock seconds]
	dict set dbh hdl lastupd_date $data
	set data [clock format $data -format "%Y %m %d" -timezone ":UTC"]
	puts -nonewline $fh [binary format c [expr {[lindex $data 0] - 1900}]]
	puts -nonewline $fh [binary format c [lindex $data 1]]
	puts -nonewline $fh [binary format c [lindex $data 2]]

	# Number of records
	dict set dbh hdr rec_cnt 0
	puts -nonewline $fh [binary format i 0]

	# Size of header
	set data [expr {32 + 32 * [llength [dict get $dbh hdr fdesc]] + 1}]
	if {$data >= [expr {2**16}]} {
		error "Header size is bigger than [expr {2**16}]: $data"
	}
	dict set dbh hdr hdr_size $data
	puts -nonewline $fh [binary format s $data]

	# Size of record
	set data 1
	foreach f1desc [dict get $dbh hdr fdesc] {
		incr data [dict get $f1desc size]
	}
	if {$data >= [expr {2**16}]} {
		error "Record size is bigger than [expr {2**16}]: $data"
	}
	dict set dbh hdr rec_size $data
	puts -nonewline $fh [binary format s $data]

	for {set cnt [expr {32 - [tell $fh]}]} {$cnt} {incr cnt -1} {
		puts -nonewline $fh [binary format c 0]
	}

	_fdesc_write dbh

	seek $fh [dict get $dbh hdr hdr_size] start
	puts -nonewline $fh \x1a
}

proc _fdesc_write {_dbh} {
	upvar $_dbh dbh
	set idx 0
	set fdesc [list]

	set fh [dict get $dbh fh]
	seek $fh 32 start

	foreach f1desc [dict get $dbh hdr fdesc] {
		# Field name
		set data [dict get $f1desc name]
		set cnt [string length $data]
		if {$cnt > 11} {
			error "Field name is bigger than 11 bytes: $data"
		}
		set cnt [expr {11 - $cnt}]
		for {} {$cnt > 0} {incr cnt -1} {
			append data \x00
		}
		puts -nonewline $fh $data

		# Field type
		set data [dict get $f1desc type]
		if {[lsearch -exact {C D F N L} $data] < 0} {
			error "Field type for '[dict get $f1desc name]' is unknown: $data"
		}
		puts -nonewline $fh $data

		# Not used
		puts -nonewline $fh "\x00\x00\x00\x00"

		# Field size
		set data [dict get $f1desc size]
		if {$data > 255} {
			error [string cat "Field size for '[dict get $f1desc name]' " \
			  "is bigger than 255: $data"
		}
		puts -nonewline $fh [binary format c $data]

		# Not used
		set data ""
		for {set cnt [expr {32 - 17}]} {$cnt > 0} {incr cnt -1} {
			append data \x00
		}
		puts -nonewline $fh $data
	}
	puts -nonewline $fh "\x0d"
}

proc _rec_read {_dbh idx} {
	upvar $_dbh dbh
	set rec [dict create idx $idx]

	set fh [dict get $dbh fh]
	set pos [dict get $dbh hdr hdr_size]
	incr pos [expr {$idx*[dict get $dbh hdr rec_size]}]
	seek $fh $pos start

	set data [read $fh 1]
	if {[string length $data] != 1} {
		error [string cat "File end too early: can't read record: "\
		  "can't read a field deletion flag for $idx"]
	}
	switch -- $data {
	"*" {
		dict set rec is_del 1
	}
	" " {
		dict set rec is_del 0
	}
	"\x1a" {
		return $rec
	}
	default {
		error "Unknown value of deletion flag for $idx: $data"
	}
	}

	foreach f1desc [dict get $dbh hdr fdesc] {
		set data [read $fh [dict get $f1desc size]]
		if {[string length $data] != [dict get $f1desc size]} {
			error [string cat "File end too early: can't read record: "\
			  "can't read a field [dict get $f1desc name] for $idx"]
		}
		switch -- [dict get $f1desc type] {
		C {
			set data [encoding convertfrom [dict get $dbh opts charset] $data]
		}
		D -
		F -
		N {
			set data [string trim $data]
		}
		L {
			switch -- $data {
			Y -
			y -
			T -
			t {
				set data 1
			}
			N -
			n -
			F -
			f {
				set data 0
			}
			? {
				set data ""
			}
			}
		}
		}
		dict set rec f [dict get $f1desc name] $data
	}

	return $rec
}

proc _rec_append {_dbh rec {meta ""}} {
	upvar $_dbh dbh
	set fh [dict get $dbh fh]

	set rec_cnt [dict get $dbh hdr rec_cnt]

	__rec_write dbh $rec_cnt $rec $meta 0
	incr rec_cnt
	set pos [dict get $dbh hdr hdr_size]
	incr pos [expr {$rec_cnt*[dict get $dbh hdr rec_size]}]
	seek $fh $pos start
	puts -nonewline $fh "\x1a"

	dict set dbh hdr rec_cnt $rec_cnt
	seek $fh 4 start
	puts -nonewline $fh [binary format i $rec_cnt]

	if {[dict get $dbh opts autoflush]} {
		::dbf::flush dbh
	}

	return [expr {$rec_cnt-1}]
}

proc _rec_write {_dbh idx rec {meta ""}} {
	upvar $_dbh dbh

	__rec_write dbh $idx $rec $meta 1
}

proc __rec_write {_dbh idx rec meta mode} {
	upvar $_dbh dbh

	set fh [dict get $dbh fh]
	set pos [dict get $dbh hdr hdr_size]
	incr pos [expr {$idx*[dict get $dbh hdr rec_size]}]
	seek $fh $pos start

	if {[dict get $dbh opts check_fieldnames_on_write]} {
		set rec_info [dict create]
		foreach f1desc [dict get $dbh hdr fdesc] {
			if {[dict exists $rec [dict get $f1desc name]]} {
				dict set rec_info [dict get $f1desc name] 1
			}
		}
		dict for {k v} $rec {
			if {![dict exists $rec_info $k]} {
				error "Unknown field name: $k"
			}
		}
	}

	# Write deletion flag
	if {[dict exists $meta is_del]} {
		switch -- [dict get $meta is_del] {
		0 {
			set data " "
		}
		1 {
			set data "*"
		}
		default {
			error "Unknown value of deletion flag: [dict get $meta is_del]
		}
		}
	} else {
		set data " "
	}
	puts -nonewline $fh $data

	set err_on_missed 0
	switch $mode {
	0 {
		if {![dict get $dbh opts missed_field_is_empty_on_append]} {
			set err_on_missed 1
		}
	}
	1 {
		if {![dict get $dbh opts missed_field_is_unchanged_on_write]} {
			set err_on_missed 1
		}
	}
	default {
		error "Wrong mode value: $mode"
	}
	}
	foreach f1desc [dict get $dbh hdr fdesc] {
		if {[dict exists $rec [dict get $f1desc name]]} {
			set data [dict get $rec [dict get $f1desc name]]
		} else {
			if {$err_on_missed} {
				error "Field value for '[dict get $f1desc name]' is missed"
			}
			switch $mode {
			0 {
				set data ""
			}
			1 {
				seek $fh [dict get $f1desc size] current
				continue
			}
			}
		}
		switch -- [dict get $f1desc type] {
		C {
			set data [encoding convertto [dict get $dbh opts charset] $data]
		}
		D {
			set data [join [split [string trim $data] -.] ""]
		}
		F -
		N {
			set data [string trim $data]
			if {![regexp {^(\+|-)?[0-9]*(\.[0-9]+)?$} $data]} {
				error [string cat "Field value for '[dict get $f1desc name]' "\
				  "is wrong: $data"]
			}
		}
		L {
			switch -- $data {
			0 {
				set data "N"
			}
			1 {
				set data "Y"
			}
			"" {
				set data "?"
			}
			default {
				error [string cat "Field value for '[dict get $f1desc name]'"\
				  " is wrong: $data"]
			}
			}
		}
		}

		set cnt [expr {[dict get $f1desc size] - [string length $data]}]
		if {$cnt < 0} {
			error [string cat "Field value size for '[dict get $f1desc name]'"\
			  " is bigger than [dict get $f1desc size]: [string length $data]"]
		}
		puts -nonewline $fh $data

		# Pad with spaces
		set data ""
		for {} {$cnt > 0} {incr cnt -1} {
			append data " "
		}
		puts -nonewline $fh $data

	}

	if {[dict get $dbh opts autoflush]} {
		::dbf::flush dbh
	}
}

proc _rec_rm {_dbh idx} {
	upvar $_dbh dbh

	set fh [dict get $dbh fh]
	set pos [dict get $dbh hdr hdr_size]
	incr pos [expr {$idx*[dict get $dbh hdr rec_size]}]
	seek $fh $pos start

	# Write deletion flag
	puts -nonewline $fh "*"

	if {[dict get $dbh opts autoflush]} {
		::dbf::flush dbh
	}
}
}
