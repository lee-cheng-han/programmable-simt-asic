# Build bounded constant trees after generic synthesis-buffer cleanup.
proc build_constant_buffer_tree {net_name max_fanout} {
  set level 0
  while {1} {
    set root_net [get_nets $net_name]
    set loads [get_pins -of_objects $root_net -filter {direction == input}]
    set load_count [llength $loads]
    if {$load_count <= $max_fanout} {
      puts "Constant tree $net_name root fanout $load_count, levels $level"
      return
    }

    set group 0
    for {set first 0} {$first < $load_count} {incr first $max_fanout} {
      set last [expr {min($first + $max_fanout - 1, $load_count - 1)}]
      set load_group [lrange $loads $first $last]
      insert_buffer -buffer_cell sg13g2_buf_4 -net $root_net \
        -load_pins $load_group \
        -buffer_name ${net_name}tree_l${level}_g${group} \
        -net_name ${net_name}tree_l${level}_g${group}_net
      incr group
    }
    puts "Constant tree $net_name level $level: $load_count loads -> $group buffers"
    incr level
  }
}

build_constant_buffer_tree one_ 32
build_constant_buffer_tree zero_ 32

# Timing-driven global placement removes generic buffers before rebuilding its
# own network.  These trees encode required constant-net topology, so preserve
# them across that cleanup.
set constant_tree_cells [get_cells -hierarchical *tree_l*]
set_dont_touch $constant_tree_cells
puts "Protected [llength $constant_tree_cells] constant-tree buffers"
