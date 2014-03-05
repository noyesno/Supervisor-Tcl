#!/bin/env tclsh

package require Tcl 8.5
package require Tclx

set lut [dict create]

proc fork_child {setting} {

  array set config $setting
  set pid -1
  catch {set pid [fork]}
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
      # if [info exists $config(stdout)] {
      #   close stdout
      #   open $config(stdout) "w"
      # }
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
}

set program [dict create]
dict set program command "tail -f /dev/null"
dict set program name "demo-tail"

set program [dict merge ${program.default} $program]
fork_child $program

wait_child

vwait forever

