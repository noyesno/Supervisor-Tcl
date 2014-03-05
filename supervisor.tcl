#!/bin/env tclsh

package require Tcl 8.5
package require Tclx

set lut [dict create]

proc redirect_stdio {args} {
  # > 2> >& >> 2>> >>& 2>@1
  # | |&
  # TODO: use [join $args] to handle either 1 single arg or many args

  # TODO: not work { close stdout  ; open $file w }
  foreach {mode file} $args {
    switch -exact $mode {
      "|"     { dup $wstdout stdout ; break }
      "2|"    { dup $wstderr stderr ; break }
      "|&"    { dup $wstdout stdout ; dup $wstderr stderr ; break }
      ">"     { dup [open $file "w"] stdout }
      "2>"    { dup [open $file "w"] stderr }
      ">&"    { dup [open $file "w"] stdout ; dup stdout stderr }
      ">>"    { dup [open $file "a"] stdout }
      "2>>"   { dup [open $file "a"] stderr }
      ">>&"   { dup [open $file "a"] stdout ; dup stdout stderr }
      "2>@1"  { dup stdout stderr }
      default {
        # Error
      }
    }
  }
}

proc pipe_stdio {args} {
  # TODO
  pipe rstdout wstdout
  pipe rstderr wstderr
}

proc fork_child {setting} {
  array set config $setting

  set pid -1 ; catch {set pid [fork]}
  switch $pid {
    -1 {
      # fork fail
    }
    0 {
      # child
      if [info exists config(dir)] {
        cd $config(dir)
      }
      if [info exists config(umask)] {
        umask $config(umask)
      }
      if [info exists config(env)] {
        array set ::env $config(env)
      }

      #-- id process group set

      #---------------------------------
      # Redirect IO
      #---------------------------------
      redirect_stdio {*}$config(stdio)
      #catch { redirect_stdio {*}$config(stdio) }

      execl -argv0 $config(name) [lindex $config(command) 0] [lrange $config(command) 1 end]
    }
    default {
      # parent
      puts "DEBUG: CHILD pid = $pid"
      dict set ::lut pid:$pid $setting
    }
  }
}


proc wait_child {} {
  if [catch {set status [wait -nohang]}] {
    # puts "DEBUG: No Child"
    after 1000 wait_child
    return
  }

  if [lempty $status] {
    after 1000 wait_child
    return
  }

  puts "DEBUG: $status"
  lassign $status pid type code
  set setting [dict get $::lut pid:$pid]
  dict unset ::lut pid:$pid
  switch $type {
    EXIT {
      # TODO
    }
    SIG  {
      if {[dict get $setting restart]} {
        fork_child $setting
      }
    }
  }

  after 1000 wait_child
}

#======================================================

set program.default {
  priority 0
  start    1
  restart  0
  numprocs 1
  stdio    ""
}

set program [dict create]
dict set program command "tail -f /dev/null"
dict set program name "demo-tail"
#dict set program stdio "> /tmp/demo-tail.log 2> /tmp/demo-tail.err"
dict set program stdio ">& /tmp/demo-tail.stdio"

set program [dict merge ${program.default} $program]
fork_child $program

wait_child

vwait forever

exit

#======================================================#
# TODO:                                                #
#======================================================#

  * load from a config file
  * put process into process group

