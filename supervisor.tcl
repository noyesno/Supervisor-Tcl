#!/bin/env tclsh

package require Tcl 8.5
package require Tclx
package require tcllib
package require inifile

set lut    [dict create]
set config [dict create]

proc redirect_stdio {args} {
  # > 2> >& >> 2>> >>& 2>@1
  # | |&
  # TODO: use [join $args] to handle either 1 single arg or many args

  # TODO: not work { close stdout  ; open $file w }
  set stdout "" ; set stderr ""
  foreach {mode file} $args {
    switch -exact $mode {
      "|"     { set stdout [dict get $::pstdout output] }
      "|2"    { set stderr [dict get $::pstderr output] }
      "|&"    {
        set stdout [dict get $::pstdout output]
        set stderr [dict get $::pstderr output]
      }
      ">"     { set stdout [open $file "w"] }
      "2>"    { set stderr [open $file "w"] }
      ">&"    { set stdout [open $file "w"] ; set stderr stdout }
      ">>"    { set stdout [open $file "a"] }
      "2>>"   { set stderr [open $file "a"] }
      ">>&"   { set stdout [open $file "a"] ; set stderr stdout }
      "2>@1"  { set stderr stdout }
      default {
        # Error
      }
    }
  }
  # TODO: check stderr same destination file as stdout
  if {$stdout ne ""} { dup $stdout stdout }
  if {$stderr ne ""} { dup $stderr stderr }
  if {$::pstdout ne ""} {
    close [dict get $::pstdout output] ; close [dict get $::pstdout input]
  }
  if {$::pstderr ne ""} {
    close [dict get $::pstderr output] ; close [dict get $::pstderr input]
  }
}

proc read_pipe {chan} {
    set data [read $chan]
    puts -nonewline "[string length $data] $data"
    if {[eof $chan]} {
        fileevent $chan readable {}
    }
}

proc pipe_stdio {args} {
  set ::pstdout "" ; set ::pstderr ""

  # TODO
  set stdout "" ; set stderr ""
  foreach {mode file} $args {
    switch -exact $mode {
      "|"     { set stdout $file }
      "|2"    { set stderr $file }
      "|&"    { set stdout $file ; set stderr stdout }
      default {
        # Error
      }
    }
  }

  if {$stdout ne ""} {
    pipe input output
    set ::pstdout [dict create input $input output $output]

    if {$stderr eq "stdout"} {
      set ::pstderr [dict create input [dup $input] output [dup $output]]
    }

    fconfigure $input -blocking 0 ;# -encoding binary
    fileevent  $input readable [list read_pipe $input]
  }

  # TODO: check same file as stdout
  if {$stderr ne "" && $stderr ne "stdout"} {
    pipe input output
    set ::pstderr [dict create input $input output $output]
    fconfigure $input -blocking 0 ;# -encoding binary
    fileevent  $input readable [list read_pipe $input]
  }
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

  pipe_stdio {*}$config(stdio)
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
      puts "DEBUG: CHILD pid = $pid , PPID = [pid]"  ;# PGID
      if {$::pstdout ne ""} {
        close [dict get $::pstdout output]
      }
      if {$::pstderr ne ""} {
        close [dict get $::pstderr output]
      }
      # TODO: stdin
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

proc load_config {{file "supervisor.ini"}} {
  set ini [ini::open $file]
  foreach section [ini::sections $ini] {
    dict set ::config $section [ini::get $ini $section]

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

proc daemon {{nochdir 1} {noclose 1}} {
  set pid [fork]
  if {$pid == -1} {
    # fork fail
    return
  }
  if {$pid>0} {
    # parent
    puts "daemon pid = $pid"
    exit
  }
  # child

  close stdin ;
  open /dev/null "RDWR"
  dup stdin stdout
  dup stdin stderr
}

proc on_signal {signame} {
  switch $signame {
    SIGTERM { # 15
      puts "DEBUG: sig = $signame BEGIN"
      # TODO
      kill -pgroup SIGTERM 0
      after 2000
      kill -pgroup SIGKILL 0
      puts "DEBUG: sig = $signame END"
    }
    default {
      puts "DEBUG: sig = $signame"
    }
  }
}

#======================================================

load_config

if [dict get $config supervisor daemon] {
  daemon
}

signal trap {TERM} "on_signal %S"

close stdout
open supervisor.log w
fconfigure stdout -buffering line

set program_queue [list]
foreach section [dict keys $lut program:*] {
  set program [dict merge ${program.default} [dict get $lut $section ]]
  lappend program_queue [list $program [dict get $program priority]]
}

set program_queue [lsort -index 1 -integer -decr $program_queue]
foreach program $program_queue {
  lassign $program program priority
  puts "DEBUG: $program"
  if ![dict get $program start] {
    continue
  }
  fork_program $program
}

puts [string repeat "-" 72]
system pstree -a [pid]
puts [string repeat "-" 72]

wait_child
vwait forever
exit

#======================================================#
# TODO:                                                #
#======================================================#

  - load from a config file
  + put process into process group

