Overview
========

A pure tcl lib for working with dbf format. Now only dbf3 without memo and
indexes is supported.

Synopsis
========

package require dbf

dbf::open  FILENAME [OPTS]

dbf::create FILENAME FIELDS\_DESC [OPTS]

dbf::close DBH

dbf::rec\_append DBH REC [META]

dbf::rec\_read DBH IDX

dbf::rec\_write DBH IDX REC [META]

dbf::rec\_rm DBH IDX

dbf::flush DBH

Description
===========

To create dbf file use dbf::create routine. Where:
- FILENAME is a name of dbf file;
- FIELDS\_DESC - fields description; a list where each element is a dict with
  members:
  - name - a field name
  - type - a field type (see below)
  - size - a field size in bytes
- OPTS - a dict with options:
  - charset
      by default: "ascii"
      a charset for text data
  - missed\_field\_is\_empty\_on\_append
      by default: 1
      0 or 1; if 0, then missed field on append cause an error
  - missed\_field\_is\_unchanged\_on\_write
      by default: 1
      0 or 1; if 0, then missed field on append cause an error
  - check\_fieldnames\_on\_write
      by default: 1
	  0 or 1; if 1, then before every write(or append) field names are in
	  input rec are checked against dbf fields and if there are some
	  fields in input rec that don't exist in dbf, then error is happen
  - autoflush
      by default: 1
	  0 or 1; invoke dbf::flush automatically after each update or not?
	
dbf::create return a db handle which is passed to other routines.
To open existent dbf file use dbf::open routine which accept a file name and
the same options as dbf::create and return like a dbf::create a db handle.

dbf::rec\_append can be used to append a new record to a dbf. Where:
- DBH - is a db handle(returned from dbf::create and dbf::open)
- REC - a record; a dict where a key is a field name and a value is a field
        value
- META - a record meta info(what is returned by dbf::read, a rec idx,
         is\_del flag, etc)

This routine returns a new record index which can be used in subsequent
dbf::rec\_read or dbf::rec\_write calls.

dbf::rec\_read is used to read a specified record(by index).
A return value is a dict(record with a meta info) with keys:
- idx - record index(that specified in input arguments)
- is\_del - a deletion flag
- f - record fields values; a dict(keys are field names, values are field values)

dbf::rec\_write is used to change a specified record(by index).
If missed\_field\_is\_unchanged\_on\_write option on dbf open/create is
specified, then change only fields that specified in an input record.

dbf::rec\_rm is used to mark specified record(by index) as deleted.

dbf3
====

field type and sizes:

type | size      | info
---------------------
 C   | mandatory | text
 D   | optional  | string representation of a date (size is 8 bytes)
     |           | can be YYYYMMDD, YYYY-MM-DD or YYYY.MM.DD on update
 F   | mandatory | string representation of a float
 N   | mandatory | string representation of a number(integer or float)
 L   | optional  | Boolean value, Y/y/T/t for yes, N/n/F/f for no (size is 1 byte)


Examples
========

From tclsh:

```
% set dbh [dbf::create new.dbf {{name col1 type C size 20} {name col2 type D} {name col3 type N size 10}}]
opts {charset ascii missed_field_is_empty_on_append 1 missed_field_is_unchanged_on_write 1 check_fieldnames_on_write 1 autoflush 1} hdr {version 3 fdesc {{name col1 type C size 8} {name col2 type D size 8} {name col3 type N size 10}} rec_cnt 0 hdr_size 129 rec_size 27} fh file4 hdl {_fdesc_set ::dbf::3::_fdesc_set _header_read ::dbf::3::_header_read _header_write ::dbf::3::_header_write _rec_read ::dbf::3::_rec_read _rec_append ::dbf::3::_rec_append _rec_write ::dbf::3::_rec_write _rec_rm ::dbf::3::_rec_rm lastupd_date 1656348638}
% dbf::rec_append dbh {col1 "new rec" col2 2022-06-27 col3 101}
0
% dbf::rec_append dbh {col1 "another rec" col2 2022-01-28 col3 237}
1
% dbf::rec_read dbh 0
idx 0 is_del 0 f {col1 {new rec             } col2 20220627 col3 101}
% dbf::rec_read dbh 1
idx 1 is_del 0 f {col1 {another rec         } col2 20220128 col3 237}
% dbf::close dbh
% set dbh [dbf::open new.dbf {charset cp866}]
opts {charset cp866 missed_field_is_empty_on_append 1 missed_field_is_unchanged_on_write 1 check_fieldnames_on_write 1 autoflush 1} fh file3 hdr {version 3 lastupd_date 1656374400 rec_cnt 2 hdr_size 129 rec_size 39 fdesc {{name col1 type C size 20} {name col2 type D size 8} {name col3 type N size 10}}} hdl {_fdesc_set ::dbf::3::_fdesc_set _header_read ::dbf::3::_header_read _header_write ::dbf::3::_header_write _rec_read ::dbf::3::_rec_read _rec_append ::dbf::3::_rec_append _rec_write ::dbf::3::_rec_write _rec_rm ::dbf::3::_rec_rm}
% set rec [dbf::rec_read dbh 0]
idx 0 is_del 0 f {col1 {new rec             } col2 20220627 col3 101}
% dict set rec f col1 "str is changed"
idx 0 is_del 0 f {col1 {str is changed} col2 20220627 col3 101}
% dbf::rec_write dbh 0 [dict get $rec f]
% dbf::rec_read dbh 0
idx 0 is_del 0 f {col1 {str is changed      } col2 20220627 col3 101}
% dbf::rec_write dbh 0 {col1 "only one field"}
% dbf::rec_read dbh 0
idx 0 is_del 0 f {col1 {only one field      } col2 20220627 col3 101}
% dbf::rec_write dbh 0 {} {is_del 1}
% dbf::rec_read dbh 0
idx 0 is_del 1 f {col1 {only one field      } col2 20220627 col3 101}
% dbf::rec_rm dbh 1
% dbf::rec_read dbh 1
idx 1 is_del 1 f {col1 {another rec         } col2 20220128 col3 237}
```
