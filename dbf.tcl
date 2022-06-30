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

package provide dbf 0.1

# https://www.clicketyclick.dk/databases/xbase/format/index.html
# http://www.independent-software.com/dbase-dbf-dbt-file-format.html

namespace eval dbf {
proc open {fname {opts ""}} {
	set dbh [dict create]

	dict set dbh opts [_opts_parse $opts]

	set fh [::open $fname r+]
	fconfigure $fh -translation binary
	dict set dbh fh $fh

	_header_read dbh
}

proc create {fname fdesc {opts ""} {ver 3}} {
	set dbh [dict create]

	dict set dbh opts [_opts_parse $opts]
	dict set dbh hdr [dict create\
	  version $ver]

	set fh [::open $fname w+]
	fconfigure $fh -translation binary
	dict set dbh fh $fh

	switch -- $ver {
	3 {
		package require dbf3
		::dbf::3::_setup_handlers dbh
	}
	default {
		error "Unsupported version: $ver"
	}
	}

	{*}[dict get $dbh hdl _fdesc_set] dbh $fdesc
	_header_write dbh

	return $dbh
}

proc _opts_parse {opts} {
	set opts_defaults [dict create \
	  charset ascii\
	  missed_field_is_empty_on_append 1\
	  missed_field_is_unchanged_on_write 1\
	  check_fieldnames_on_write 1\
	  autoflush 1]

	set opts [dict merge $opts_defaults $opts]
	return $opts
}

proc close {_dbh} {
	upvar $_dbh dbh

	::close [dict get $dbh fh]
}

proc flush {_dbh} {
	upvar $_dbh dbh

	::flush [dict get $dbh fh]
}

proc _header_read {_dbh} {
	upvar $_dbh dbh

	set fh [dict get $dbh fh]
	seek $fh 0 start

	set data [read $fh 1]
	if {[string length $data] != 1} {
		error "File end too early: can't read header: can't read a version"
	}
	binary scan $data c num
	dict set dbh hdr version $num

	switch -- $num {
	3 {
		package require dbf3
		::dbf::3::_setup_handlers dbh
	}
	default {
		error "Unsupported version: $num"
	}
	}

	{*}[dict get $dbh hdl _header_read] dbh
}

proc _header_write {_dbh} {
	upvar $_dbh dbh

	set fh [dict get $dbh fh]
	seek $fh 0 start

	puts -nonewline $fh [binary format c [dict get $dbh hdr version]]

	{*}[dict get $dbh hdl _header_write] dbh
}

proc rec_read {_dbh idx} {
	upvar $_dbh dbh

	return [{*}[dict get $dbh hdl _rec_read] dbh $idx]
}

proc rec_append {_dbh rec {meta ""}} {
	upvar $_dbh dbh

	return [{*}[dict get $dbh hdl _rec_append] dbh $rec $meta]
}

proc rec_write {_dbh idx rec {meta ""}} {
	upvar $_dbh dbh

	{*}[dict get $dbh hdl _rec_write] dbh $idx $rec $meta
}

proc rec_rm {_dbh idx} {
	upvar $_dbh dbh

	{*}[dict get $dbh hdl _rec_rm] dbh $idx
}
}
