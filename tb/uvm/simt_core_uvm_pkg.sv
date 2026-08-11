package simt_core_uvm_pkg;
  import uvm_pkg::*;
  import simt_gpu_pkg::*;
  `include "uvm_macros.svh"

  typedef enum {CORE_PROGRAM, CORE_LAUNCH, CORE_CLEAR} core_command_t;

  class core_command extends uvm_sequence_item;
    `uvm_object_utils(core_command)
    core_command_t command;
    rand bit [5:0] address;
    rand bit [31:0] data;
    rand bit [2:0] warp_count;
    rand bit [31:0] launch_pc;
    function new(string name="core_command"); super.new(name); endfunction
  endclass

  class commit_item extends uvm_sequence_item;
    `uvm_object_utils(commit_item)
    completion_record_t record;
    string canonical;
    function new(string name="commit_item"); super.new(name); endfunction
  endclass

  class arithmetic_sequence extends uvm_sequence #(core_command);
    `uvm_object_utils(arithmetic_sequence)
    localparam bit [31:0] PROGRAM [6] = '{
      32'h74040001, 32'h38080003, 32'h040c4800,
      32'h0c10c800, 32'h04150c00, 32'h78000000
    };
    function new(string name="arithmetic_sequence"); super.new(name); endfunction
    task body();
      core_command item;
      int program_file=$fopen("build/uvm/program.hex","w");
      if(!program_file) `uvm_fatal("PROGRAM","cannot write generated program")
      foreach (PROGRAM[index]) begin
        $fdisplay(program_file,"%08x",PROGRAM[index]);
        item=core_command::type_id::create($sformatf("program_%0d",index));
        start_item(item); item.command=CORE_PROGRAM; item.address=6'(index);
        item.data=PROGRAM[index]; finish_item(item);
      end
      item=core_command::type_id::create("launch");
      start_item(item); item.command=CORE_LAUNCH; item.warp_count=3'd4;
      item.launch_pc='0; finish_item(item);
      $fclose(program_file);
    endtask
  endclass

  class random_integer_instruction extends uvm_object;
    `uvm_object_utils(random_integer_instruction)
    rand bit [5:0] opcode;
    rand bit [3:0] rd,ra,rb;
    constraint legal_opcode {opcode inside {6'd1,6'd2,6'd3,6'd4,6'd5,
                                             6'd6,6'd7,6'd8};}
    constraint writable_destination {rd inside {[3:15]};}
    constraint legal_sources {ra inside {[1:15]};rb inside {[1:15]};}
    function new(string name="random_integer_instruction");super.new(name);endfunction
    function bit [31:0] encode();
      return {opcode,2'b0,rd,ra,rb,10'b0};
    endfunction
  endclass

  class constrained_random_integer_sequence extends uvm_sequence #(core_command);
    `uvm_object_utils(constrained_random_integer_sequence)
    rand int unsigned body_length;
    int unsigned instruction_count;
    constraint useful_length {body_length inside {[8:24]};}
    function new(string name="constrained_random_integer_sequence");super.new(name);endfunction
    task send_word(int unsigned index,bit[31:0]word,int file_handle);
      core_command item=core_command::type_id::create($sformatf("program_%0d",index));
      $fdisplay(file_handle,"%08x",word);
      start_item(item);item.command=CORE_PROGRAM;item.address=6'(index);
      item.data=word;finish_item(item);
    endtask
    task body();
      random_integer_instruction generated;
      core_command launch;
      int program_file=$fopen("build/uvm/program.hex","w");
      if(!program_file) `uvm_fatal("PROGRAM","cannot write generated program")
      send_word(0,32'h38040007,program_file);
      send_word(1,32'h38080003,program_file);
      for(int unsigned index=0;index<body_length;index++)begin
        generated=random_integer_instruction::type_id::create($sformatf("instruction_%0d",index));
        if(!generated.randomize()) `uvm_fatal("RANDOMIZE","instruction randomization failed")
        send_word(index+2,generated.encode(),program_file);
      end
      send_word(body_length+2,32'h78000000,program_file);
      instruction_count=body_length+3;
      $fclose(program_file);
      launch=core_command::type_id::create("launch");
      start_item(launch);launch.command=CORE_LAUNCH;launch.warp_count=3'd4;
      launch.launch_pc='0;finish_item(launch);
    endtask
  endclass

  class core_driver extends uvm_driver #(core_command);
    `uvm_component_utils(core_driver)
    virtual simt_core_if vif;
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","core_driver requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      core_command item;
      vif.clear=0; vif.prog_valid=0;
      vif.launch_valid=0; vif.launch_pc=0;
      vif.launch_warp_count=0;
      while(vif.rst) @(negedge vif.clk);
      `uvm_info("DRIVER","reset released; command driver active",UVM_LOW)
      forever begin
        seq_item_port.get(item);
        `uvm_info("DRIVER",$sformatf("command=%0d",item.command),UVM_HIGH)
        case(item.command)
          CORE_PROGRAM: begin
            vif.prog_addr=item.address; vif.prog_data=item.data;
            vif.prog_valid=1; @(negedge vif.clk); vif.prog_valid=0;
          end
          CORE_LAUNCH: begin
            vif.launch_pc=item.launch_pc;
            vif.launch_warp_count=item.warp_count;
            while(vif.launch_ready!==1'b1) @(negedge vif.clk);
            vif.launch_valid=1; @(negedge vif.clk); vif.launch_valid=0;
          end
          CORE_CLEAR: begin
            vif.clear=1; @(negedge vif.clk); vif.clear=0;
          end
        endcase
      end
    endtask
  endclass

  class commit_monitor extends uvm_monitor;
    `uvm_component_utils(commit_monitor)
    virtual simt_core_if vif;
    uvm_analysis_port #(commit_item) analysis_port;
    function new(string name,uvm_component parent);
      super.new(name,parent); analysis_port=new("analysis_port",this);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","commit_monitor requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      commit_item item;
      forever begin
        @(negedge vif.clk);
        if(vif.fault)
          `uvm_error("CORE_FAULT",$sformatf("code=%0d pc=%0d",
                     vif.fault_code,vif.fault_pc))
        if(vif.commit_valid) begin
          item=commit_item::type_id::create("commit");
          item.record.valid=vif.commit.valid;
          item.record.epoch=vif.commit.epoch;
          item.record.warp_id=vif.commit.warp_id;
          item.record.sequence_number=vif.commit.sequence_number;
          item.record.pc=vif.commit.pc;
          item.record.instruction=vif.commit.instruction;
          item.record.active_mask=vif.commit.active_mask;
          item.record.write_mask=vif.commit.write_mask;
          item.record.writes_gpr=vif.commit.writes_gpr;
          item.record.gpr_dst=vif.commit.gpr_dst;
          item.record.gpr_mask=vif.commit.gpr_mask;
          foreach(item.record.gpr_data[lane])
            item.record.gpr_data[lane]=vif.commit.gpr_data[lane];
          item.record.writes_pred=vif.commit.writes_pred;
          item.record.pred_dst=vif.commit.pred_dst;
          item.record.pred_mask=vif.commit.pred_mask;
          item.record.pred_data=vif.commit.pred_data;
          item.record.clear_gpr_pending=vif.commit.clear_gpr_pending;
          item.record.clear_pred_pending=vif.commit.clear_pred_pending;
          item.record.completion_class=vif.commit.completion_class;
          item.record.status=vif.commit.status;
          item.canonical=$sformatf("C %0d %0d %0d %08x %08x %02x %02x %0d %0d %02x",
            item.record.epoch,item.record.warp_id,item.record.sequence_number,
            item.record.pc,item.record.instruction,item.record.active_mask,
            item.record.write_mask,item.record.writes_gpr,item.record.gpr_dst,
            item.record.gpr_mask);
          foreach(item.record.gpr_data[lane])
            item.canonical={item.canonical,$sformatf(" %08x",item.record.gpr_data[lane])};
          item.canonical={item.canonical,$sformatf(" %0d %0d %02x %02x",
            item.record.writes_pred,item.record.pred_dst,item.record.pred_mask,
            item.record.pred_data)};
          analysis_port.write(item);
        end
      end
    endtask
  endclass

  class core_agent extends uvm_agent;
    `uvm_component_utils(core_agent)
    uvm_sequencer #(core_command) sequencer;
    core_driver driver; commit_monitor monitor;
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      sequencer=uvm_sequencer#(core_command)::type_id::create("sequencer",this);
      driver=core_driver::type_id::create("driver",this);
      monitor=commit_monitor::type_id::create("monitor",this);
    endfunction
    function void connect_phase(uvm_phase phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass

  class core_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(core_virtual_sequencer)
    uvm_sequencer #(core_command) core_sequencer;
    virtual simt_core_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","virtual sequencer requires simt_core_if")
    endfunction
  endclass

  class clear_relaunch_virtual_sequence extends uvm_sequence;
    `uvm_object_utils(clear_relaunch_virtual_sequence)
    `uvm_declare_p_sequencer(core_virtual_sequencer)
    function new(string name="clear_relaunch_virtual_sequence");super.new(name);endfunction
    task body();
      arithmetic_sequence first=arithmetic_sequence::type_id::create("first");
      arithmetic_sequence second=arithmetic_sequence::type_id::create("second");
      core_command clear_command=core_command::type_id::create("clear");
      first.start(p_sequencer.core_sequencer);
      do @(negedge p_sequencer.vif.clk); while(!p_sequencer.vif.done);
      start_item(clear_command,-1,p_sequencer.core_sequencer);
      clear_command.command=CORE_CLEAR;finish_item(clear_command);
      second.start(p_sequencer.core_sequencer);
    endtask
  endclass

  class core_functional_coverage extends uvm_subscriber #(commit_item);
    `uvm_component_utils(core_functional_coverage)
    bit [5:0] sampled_opcode;
    bit [1:0] sampled_warp;
    bit [1:0] sampled_source;
    bit sampled_predicated;
    bit [7:0] sampled_mask;
    covergroup architectural_commits;
      option.per_instance=1;
      opcode: coverpoint sampled_opcode {
        bins integer_alu[]={[1:15]}; bins predicate[]={[16:21]};
        bins control[]={26,27,29,30,31}; illegal_bins memory[]={22,23,24,25,28};
      }
      warp: coverpoint sampled_warp {bins resident[]={0,1,2,3};}
      source: coverpoint sampled_source {bins alu={0};bins multiplier={1};}
      predicated: coverpoint sampled_predicated;
      mask_class: coverpoint sampled_mask {
        bins empty={8'h00};bins full={8'hff};bins low_high={8'h0f,8'hf0};
        bins sparse=default;
      }
      opcode_by_warp: cross opcode,warp;
      source_by_warp: cross source,warp;
      opcode_by_mask: cross opcode,mask_class;
    endgroup
    function new(string name,uvm_component parent);
      super.new(name,parent);architectural_commits=new;
    endfunction
    function void write(commit_item t);
      sampled_opcode=t.record.instruction[31:26];
      sampled_warp=t.record.warp_id;
      sampled_source=t.record.completion_class;
      sampled_predicated=t.record.instruction[25];
      sampled_mask=t.record.write_mask;
      architectural_commits.sample();
    endfunction
  endclass

  class differential_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(differential_scoreboard)
    uvm_analysis_imp #(commit_item,differential_scoreboard) analysis_export;
    int trace_file, observed;
    int expected_sequence[int];
    function new(string name,uvm_component parent);
      super.new(name,parent); analysis_export=new("analysis_export",this);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      trace_file=$fopen("build/uvm_four_warp.trace","w");
      if(!trace_file) `uvm_fatal("TRACE","cannot open UVM architectural trace")
    endfunction
    function void write(commit_item item);
      int warp=int'(item.record.warp_id);
      if(item.record.sequence_number!=16'(expected_sequence[warp]))
        `uvm_error("SEQUENCE",$sformatf("warp=%0d got=%0d expected=%0d",warp,
                   item.record.sequence_number,expected_sequence[warp]))
      expected_sequence[warp]++; observed++; $fdisplay(trace_file,"%s",item.canonical);
    endfunction
    function void final_phase(uvm_phase phase);
      $fclose(trace_file);
      if(observed==0) `uvm_error("COUNT","no architectural commits observed")
      if(expected_sequence.num()!=4)
        `uvm_error("WARP_COUNT",$sformatf("observed warps=%0d expected=4",expected_sequence.num()))
      foreach(expected_sequence[warp])
        if(expected_sequence[warp]!=(observed/4))
          `uvm_error("WARP_COUNT",$sformatf("warp=%0d commits=%0d expected=%0d",
                     warp,expected_sequence[warp],observed/4))
    endfunction
  endclass

  class core_env extends uvm_env;
    `uvm_component_utils(core_env)
    core_agent agent; core_virtual_sequencer virtual_sequencer;
    differential_scoreboard scoreboard; core_functional_coverage coverage;
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent=core_agent::type_id::create("agent",this);
      virtual_sequencer=core_virtual_sequencer::type_id::create("virtual_sequencer",this);
      scoreboard=differential_scoreboard::type_id::create("scoreboard",this);
      coverage=core_functional_coverage::type_id::create("coverage",this);
    endfunction
    function void connect_phase(uvm_phase phase);
      agent.monitor.analysis_port.connect(scoreboard.analysis_export);
      agent.monitor.analysis_port.connect(coverage.analysis_export);
      virtual_sequencer.core_sequencer=agent.sequencer;
    endfunction
  endclass

  class four_warp_differential_test extends uvm_test;
    `uvm_component_utils(four_warp_differential_test)
    core_env env; virtual simt_core_if vif;
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase); env=core_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","test requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      arithmetic_sequence test_sequence=arithmetic_sequence::type_id::create("test_sequence");
      phase.raise_objection(this);
      `uvm_info("TEST","starting arithmetic sequence",UVM_LOW)
      test_sequence.start(env.agent.sequencer);
      `uvm_info("TEST","arithmetic sequence completed",UVM_LOW)
      repeat(400) begin @(negedge vif.clk); if(vif.done) break; end
      if(!vif.done) `uvm_error("TIMEOUT","kernel did not complete")
      if(vif.fault) `uvm_error("FAULT","kernel completed with fault")
      if(vif.issue_count!=24||vif.commit_count!=24)
        `uvm_error("COUNTERS",$sformatf("issue=%0d commit=%0d",
                   vif.issue_count,vif.commit_count))
      phase.drop_objection(this);
    endtask
  endclass

  class constrained_random_differential_test extends uvm_test;
    `uvm_component_utils(constrained_random_differential_test)
    core_env env;virtual simt_core_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);env=core_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","test requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      constrained_random_integer_sequence test_sequence=
        constrained_random_integer_sequence::type_id::create("test_sequence");
      phase.raise_objection(this);
      if(!test_sequence.randomize()) `uvm_fatal("RANDOMIZE","sequence randomization failed")
      test_sequence.start(env.agent.sequencer);
      repeat(1200) begin @(negedge vif.clk); if(vif.done) break; end
      if(!vif.done) `uvm_error("TIMEOUT","random kernel did not complete")
      if(vif.fault) `uvm_error("FAULT","random kernel faulted")
      if(vif.issue_count!=64'(test_sequence.instruction_count*4)||
         vif.commit_count!=64'(test_sequence.instruction_count*4))
        `uvm_error("COUNTERS",$sformatf("instructions=%0d issue=%0d commit=%0d",
          test_sequence.instruction_count,vif.issue_count,
          vif.commit_count))
      phase.drop_objection(this);
    endtask
  endclass
endpackage
