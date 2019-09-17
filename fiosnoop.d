#!/bin/bash
#
# fiosnoop.d - snoop file read, write, and delete events
#              Written using DTrace (Solaris 11.3)
#
# This script provides visibility to logical file read, write events,
# as well as file-delete events.
#
# USAGE:       fiosnoop.d
#
# IDEA: iosnoop and rfileio.d from Brendan Gregg's DTrace Toolkit
#
# COPYRIGHT: Copyright (c) 2019 eFolder Inc dba Axcient
#
# CDDL HEADER START
#
#  The contents of this file are subject to the terms of the
#  Common Development and Distribution License, Version 1.0 only
#  (the "License").  You may not use this file except in compliance
#  with the License.
#
#  You can obtain a copy of the license at Docs/cddl1.txt
#  or http://www.opensolaris.org/os/licensing.
#  See the License for the specific language governing permissions
#  and limitations under the License.
#
# CDDL HEADER END
#
# 09-Sep-2019  Kevin Hoffman   Initial version
#

 ##############################
 # --- Process Arguments ---
 #

 ### default variables
 filter=0; filename=.; opt_filepart=0

 ### process options
 while getopts hF: name
 do
         case $name in
         F)      opt_filepart=1; filename=$OPTARG ;;
         h|?)    cat <<END >&2
USAGE: fiosnoop.d [-F filepart]
      fiosnoop.d       # default output
                  -F filepart     # only files whose path contain filepart
  eg,
       iosnoop -F /fs  # snoop events for files whose path contains /fs only
END
                 exit 1
         esac
 done

 ### option logic
 if [ $opt_filepart -eq 1 ]; then
         filter=1
 fi


 #################################
 # --- Main Program, DTrace ---
 #
 /usr/sbin/dtrace -n '

inline int OPT_filepart= '$opt_filepart';
inline int FILTER      = '$filter';
inline string FILENAME = "'$filename'";

#pragma D option quiet
#pragma D option dynvarsize=16m

dtrace:::BEGIN
{
    printf("T| Elapsed(us)|       Bytes|Filename\n");
}

fbt::fop_read:entry,
fbt::fop_write:entry
/args[0]->v_path/
{
    self->ok = FILTER ? 0 : 1;
    (OPT_filepart == 1 && 0 != strstr(args[0]->v_path, FILENAME)) ? self->ok = 1 : 1;
    (args[0]->v_type != 1) ? self->ok = 0 : 1;
}

fbt::fop_read:entry,
fbt::fop_write:entry
/self->ok && args[0]->v_path/
{
    self->start = timestamp;
    self->pathname = cleanpath(args[0]->v_path);
    self->size = args[1]->uio_resid;
    self->uiop = args[1];
    self->ok = 0;
}

fbt::fop_read:return
/self->size/
{
    printf("R|%12d|%12d|%s\n", (timestamp - self->start)/1000, (self->size - self->uiop->uio_resid), self->pathname);
    self->start = 0;
    self->uiop = 0;
    self->pathname = 0;
    self->size = 0;
}

fbt::fop_write:return
/self->size/
{
    printf("W|%12d|%12d|%s\n", (timestamp - self->start)/1000, (self->size - self->uiop->uio_resid), self->pathname);
    self->start = 0;
    self->uiop = 0;
    self->pathname = 0;
    self->size = 0;
}

fbt::fop_remove:entry
{
    self->ok = FILTER ? 0 : NULL != args[0] && NULL != args[0]->v_path;
    (OPT_filepart == 1 && NULL != args[0] && NULL != args[0]->v_path && 0 != strstr(args[0]->v_path, FILENAME)) ? self->ok = 1 : 1;
}

fbt::fop_remove:entry
/self->ok/
{
    self->start = timestamp;
    self->pathname = cleanpath(args[0]->v_path);
    self->entryname = cleanpath(args[1]);
}

fbt::fop_remove:return
/self->start/
{
    printf("D|%12d|%12d|%s/%s\n", (timestamp - self->start)/1000, 0, self->pathname, self->entryname);
    self->pathname = 0;
    self->entryname = 0;
    self->start = 0;
    self->ok = 0;
}

'
