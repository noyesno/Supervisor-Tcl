#!/bin/env tclsh

package require Tcl 8.5
package require Tclx
package require tcllib
package require inifile

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

#--------------------------------------------------------#
# e.g.:
#   pformat "%(name)s-%(num)02d" {name hello num 3}
#--------------------------------------------------------#
proc pformat {fmt vars} {
  set cmd [list format]
  lappend cmd [regsub -all {%\(\w+\)} $fmt "%"]
  foreach {- name} [regexp -inline -all {%\((\w+)\)} $fmt] {
    lappend cmd [dict get $vars $name]
  }
  return [ {*}$cmd ]
}

proc fork_program {setting} {
  set numprocs [dict get $setting numprocs]
  for {set i 0} {$i < $numprocs} {incr i} {
    puts [list fork_child $setting $i]
    fork_child $setting $i
  }
}

proc fork_child {setting {index 0}} {
  set vars [dict create \
    program [dict get $setting program] \
    index   $index \
  ]
  # group, host, program, index, dir

  array set config [pformat $setting $vars]

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

proc load_ini {{file "supervisor.ini"}} {
  set ini [ini::open $file]
  foreach section [ini::sections $ini] {
    if [string match "program:*" $section] {
      dict set ::lut $section [ini::get $ini $section]
      dict set ::lut $section program [lindex [split $section :] 1]
    }
  }
  ini::close $ini
}

set program.default {
  priority 0
  start    1
  restart  0
  numprocs 1
  stdio    ""
}

#======================================================

load_ini

set program_queue [list]
foreach section [dict keys $lut program:*] {
  set program [dict merge ${program.default} [dict get $lut $section ]]
  lappend program_queue [list $program [dict get $program priority]]
}

set program_queue [lsort -index 1 -integer -decr $program_queue]

foreach program $program_queue {
  lassign $program program priority
  puts "DEBUG: $program"
  fork_program $program
}

wait_child

vwait forever

exit

#======================================================#
# TODO:                                                #
#======================================================#

  - load from a config file
  + put process into process group

