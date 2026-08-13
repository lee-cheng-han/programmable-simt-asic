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
    bit execute_stall_observed;
    bit writeback_stall_observed;
    bit [2:0] resident_warps;
    function new(string name="commit_item"); super.new(name); endfunction
  endclass

  class arithmetic_sequence extends uvm_sequence #(core_command);
    `uvm_object_utils(arithmetic_sequence)
    localparam bit [31:0] PROGRAM [6] = '{
      32'h74040001, 32'h38080003, 32'h040c4800,
      32'h0c10c800, 32'h04150c00, 32'h78000000
    };
    int unsigned initial_epoch;
    function new(string name="arithmetic_sequence"); super.new(name); endfunction
    task body();
      core_command item;
      int program_file=$fopen("build/uvm/program.hex","w");
      int config_file=$fopen("build/uvm/run.cfg","w");
      if(!program_file) `uvm_fatal("PROGRAM","cannot write generated program")
      if(!config_file) `uvm_fatal("PROGRAM","cannot write run configuration")
      $fdisplay(config_file,"4 %0d",initial_epoch);
      $fclose(config_file);
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

  class stack_underflow_sequence extends uvm_sequence #(core_command);
    `uvm_object_utils(stack_underflow_sequence)
    function new(string name="stack_underflow_sequence");super.new(name);endfunction
    task body();
      core_command item=core_command::type_id::create("underflow_program");
      start_item(item);item.command=CORE_PROGRAM;item.address=0;
      item.data=32'h7c000000;finish_item(item);
      item=core_command::type_id::create("underflow_launch");
      start_item(item);item.command=CORE_LAUNCH;item.warp_count=1;
      item.launch_pc=0;finish_item(item);
    endtask
  endclass

  class memory_sequence extends uvm_sequence #(core_command);
    `uvm_object_utils(memory_sequence)
    localparam bit[31:0] PROGRAM[7]='{
      32'h38040000,32'h3808002a,32'h5c004800,32'h580c4000,
      32'h64004800,32'h60104000,32'h78000000};
    function new(string name="memory_sequence");super.new(name);endfunction
    task body();
      core_command item;int pf=$fopen("build/uvm/program.hex","w");
      int cf=$fopen("build/uvm/run.cfg","w");
      if(!pf||!cf)`uvm_fatal("PROGRAM","cannot write memory artifacts")
      $fdisplay(cf,"4");$fclose(cf);
      foreach(PROGRAM[index])begin
        $fdisplay(pf,"%08x",PROGRAM[index]);
        item=core_command::type_id::create($sformatf("program_%0d",index));
        start_item(item);item.command=CORE_PROGRAM;item.address=6'(index);
        item.data=PROGRAM[index];finish_item(item);
      end
      $fclose(pf);item=core_command::type_id::create("launch");
      start_item(item);item.command=CORE_LAUNCH;item.warp_count=4;
      item.launch_pc=0;finish_item(item);
    endtask
  endclass

  class core_clear_sequence extends uvm_sequence #(core_command);
    `uvm_object_utils(core_clear_sequence)
    function new(string name="core_clear_sequence");super.new(name);endfunction
    task body();
      core_command item=core_command::type_id::create("clear");
      start_item(item);item.command=CORE_CLEAR;finish_item(item);
    endtask
  endclass

  class random_integer_instruction extends uvm_object;
    `uvm_object_utils(random_integer_instruction)
    rand bit [5:0] opcode;
    rand bit [3:0] rd,ra,rb;
    int unsigned max_source=2;
    constraint legal_opcode {opcode inside {6'd1,6'd2,6'd3,6'd4,6'd5,
                                             6'd6,6'd7,6'd8};}
    constraint writable_destination {rd inside {[3:15]};}
    constraint legal_sources {ra inside {[1:max_source]};
                              rb inside {[1:max_source]};}
    function new(string name="random_integer_instruction");super.new(name);endfunction
    function bit [31:0] encode();
      return {opcode,4'b0,rd,ra,rb,10'b0};
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
      int config_file=$fopen("build/uvm/run.cfg","w");
      if(!program_file) `uvm_fatal("PROGRAM","cannot write generated program")
      if(!config_file) `uvm_fatal("PROGRAM","cannot write run configuration")
      $fdisplay(config_file,"4");
      $fclose(config_file);
      send_word(0,32'h38040007,program_file);
      send_word(1,32'h38080003,program_file);
      for(int unsigned index=0;index<body_length;index++)begin
        generated=random_integer_instruction::type_id::create($sformatf("instruction_%0d",index));
        generated.max_source=(index<13)?index+2:15;
        if(!generated.randomize()) `uvm_fatal("RANDOMIZE","instruction randomization failed")
        if(index<13) generated.rd=4'(index+3);
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

  class structured_control_sequence extends uvm_sequence #(core_command);
    `uvm_object_utils(structured_control_sequence)
    rand bit nested;
    rand bit [2:0] warp_count;
    int unsigned instruction_count;
    constraint resident_warps {warp_count inside {[1:4]};}
    localparam bit [31:0] SHALLOW [10] = '{
      32'h74040003,32'h38080004,32'h48004800,32'h6c000004,
      32'h6a000002,32'h380c0009,32'h68000001,32'h380c0005,
      32'h7c000000,32'h78000000};
    localparam bit [31:0] NESTED [17] = '{
      32'h74040003,32'h38080004,32'h48004800,32'h6c00000b,
      32'h6a000002,32'h3810005a,32'h68000008,32'h380c0002,
      32'h48044c00,32'h6c000004,32'h6a400002,32'h3810001e,
      32'h68000001,32'h3810000a,32'h7c000000,32'h7c000000,
      32'h78000000};
    function new(string name="structured_control_sequence");super.new(name);endfunction
    task send_word(int unsigned index,bit[31:0]word,int file_handle);
      core_command item=core_command::type_id::create($sformatf("program_%0d",index));
      $fdisplay(file_handle,"%08x",word);
      start_item(item);item.command=CORE_PROGRAM;item.address=6'(index);
      item.data=word;finish_item(item);
    endtask
    task body();
      core_command launch;
      int program_file=$fopen("build/uvm/program.hex","w");
      int config_file=$fopen("build/uvm/run.cfg","w");
      if(!program_file||!config_file)
        `uvm_fatal("PROGRAM","cannot write structured-control artifacts")
      $fdisplay(config_file,"%0d",warp_count);$fclose(config_file);
      if(nested) begin
        foreach(NESTED[index]) send_word(index,NESTED[index],program_file);
        instruction_count=19;
      end else begin
        foreach(SHALLOW[index]) send_word(index,SHALLOW[index],program_file);
        instruction_count=11;
      end
      $fclose(program_file);
      launch=core_command::type_id::create("launch");
      start_item(launch);launch.command=CORE_LAUNCH;
      launch.warp_count=warp_count;launch.launch_pc='0;finish_item(launch);
    endtask
  endclass

  class isa_coverage_sequence extends uvm_sequence #(core_command);
    `uvm_object_utils(isa_coverage_sequence)
    int unsigned warp_count=4;
    int unsigned instruction_count;
    function new(string name="isa_coverage_sequence");super.new(name);endfunction
    function bit[31:0] rrr(bit[5:0]opcode,bit[3:0]rd,bit[3:0]ra,
                           bit[3:0]rb);
      return {opcode,4'b0,rd,ra,rb,10'b0};
    endfunction
    task send_word(int unsigned index,bit[31:0]word,int file_handle);
      core_command item=core_command::type_id::create($sformatf("program_%0d",index));
      $fdisplay(file_handle,"%08x",word);
      start_item(item);item.command=CORE_PROGRAM;item.address=6'(index);
      item.data=word;finish_item(item);
    endtask
    task body();
      core_command launch;
      bit[31:0] words[$];
      int program_file=$fopen("build/uvm/program.hex","w");
      int config_file=$fopen("build/uvm/run.cfg","w");
      if(!program_file||!config_file)
        `uvm_fatal("PROGRAM","cannot write ISA-coverage artifacts")
      $fdisplay(config_file,"%0d",warp_count);$fclose(config_file);
      words.push_back({6'd14,4'b0,4'd1,4'd0,4'd0,10'd7});
      words.push_back({6'd14,4'b0,4'd2,4'd0,4'd0,10'd3});
      for(int unsigned opcode=1;opcode<=13;opcode++) begin
        if(opcode inside {9,13}) words.push_back(rrr(6'(opcode),4'd3,4'd1,4'd0));
        else words.push_back(rrr(6'(opcode),4'd3,4'd1,4'd2));
      end
      for(int unsigned opcode=16;opcode<=21;opcode++)
        words.push_back(rrr(6'(opcode),4'd0,4'd1,4'd2));
      words.push_back({6'd15,1'b1,1'b0,2'd0,4'd3,4'd1,4'd2,10'd0});
      words.push_back({6'd29,4'b0,4'd4,4'd0,4'd0,10'd3});
      words.push_back(32'h78000000);
      foreach(words[index]) send_word(index,words[index],program_file);
      instruction_count=words.size();$fclose(program_file);
      launch=core_command::type_id::create("launch");
      start_item(launch);launch.command=CORE_LAUNCH;
      launch.warp_count=3'(warp_count);launch.launch_pc='0;finish_item(launch);
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
    bit execute_stall_since_commit;
    bit writeback_stall_since_commit;
    bit allow_expected_fault;
    bit expected_fault_observed;
    bit fault_seen;
    fault_code_t expected_fault_code;
    fault_code_t sampled_fault_code;
    covergroup fault_coverage;
      option.per_instance=1;
      fault_code: coverpoint sampled_fault_code {
        bins illegal={FAULT_ILLEGAL_INSTRUCTION};
        bins unsupported={FAULT_UNSUPPORTED_STAGE};
        bins stack_overflow={FAULT_SIMT_STACK_OVERFLOW};
        bins stack_underflow={FAULT_SIMT_STACK_UNDERFLOW};
        bins control={FAULT_SIMT_CONTROL};
      }
    endgroup
    function new(string name,uvm_component parent);
      super.new(name,parent); analysis_port=new("analysis_port",this);
      fault_coverage=new;
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","commit_monitor requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      commit_item item;
      forever begin
        @(posedge vif.clk);
        if(!vif.execute_completion_ready)
          execute_stall_since_commit=1'b1;
        if(vif.commit_valid && !vif.commit_ready)
          writeback_stall_since_commit=1'b1;
        if(vif.fault&&!fault_seen) begin
          fault_seen=1'b1;sampled_fault_code=vif.fault_code;
          fault_coverage.sample();
          if(allow_expected_fault&&vif.fault_code==expected_fault_code)
            expected_fault_observed=1'b1;
          else
            `uvm_error("CORE_FAULT",$sformatf("code=%0d pc=%0d",
                       vif.fault_code,vif.fault_pc))
        end else if(!vif.fault) fault_seen=1'b0;
        if(vif.commit_valid && vif.commit_ready) begin
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
          item.execute_stall_observed=execute_stall_since_commit;
          item.writeback_stall_observed=writeback_stall_since_commit;
          item.resident_warps=vif.launch_warp_count;
          execute_stall_since_commit=1'b0;
          writeback_stall_since_commit=1'b0;
          item.canonical=$sformatf("C %0d %0d %0d %08x %08x %02x %02x %0d %0x %02x",
            item.record.epoch,item.record.warp_id,item.record.sequence_number,
            item.record.pc,item.record.instruction,item.record.active_mask,
            item.record.write_mask,item.record.writes_gpr,
            item.record.writes_gpr?item.record.gpr_dst:0,
            item.record.gpr_mask);
          for(int lane=0;lane<LANES;lane++)
            item.canonical={item.canonical,$sformatf(" %08x",item.record.gpr_data[lane])};
          item.canonical={item.canonical,$sformatf(" %0d %0d %02x %02x",
            item.record.writes_pred,
            item.record.writes_pred?item.record.pred_dst:0,item.record.pred_mask,
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
    bit sampled_execute_stall;
    bit sampled_writeback_stall;
    bit [2:0] sampled_resident_warps;
    bit [7:0] sampled_mask;
    bit opcode_seen[64];
    bit warp_seen[4];
    bit source_seen[3];
    bit resident_warps_seen[5];
    bit mask_class_seen[4];
    bit execute_stall_seen[2];
    bit writeback_stall_seen[2];
    covergroup architectural_commits;
      option.per_instance=1;
      opcode: coverpoint sampled_opcode {
        bins integer_alu[]={[1:15]}; bins predicate[]={[16:21]};
        bins memory[]={22,23,24,25};bins control[]={26,27,29,30,31};
        illegal_bins barrier[]={28};
      }
      warp: coverpoint sampled_warp {bins resident[]={0,1,2,3};}
      source: coverpoint sampled_source {bins alu={0};bins multiplier={1};}
      predicated: coverpoint sampled_predicated;
      execute_stall: coverpoint sampled_execute_stall;
      writeback_stall: coverpoint sampled_writeback_stall;
      resident_warps: coverpoint sampled_resident_warps {
        bins counts[]={1,2,3,4};
      }
      mask_class: coverpoint sampled_mask {
        bins empty={8'h00};bins full={8'hff};bins low_high={8'h0f,8'hf0};
        bins sparse=default;
      }
      opcode_by_warp: cross opcode,warp;
      opcode_by_resident_warps: cross opcode,resident_warps;
      source_by_warp: cross source,warp;
      source_by_execute_stall: cross source,execute_stall;
      source_by_writeback_stall: cross source,writeback_stall;
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
      sampled_execute_stall=t.execute_stall_observed;
      sampled_writeback_stall=t.writeback_stall_observed;
      sampled_resident_warps=t.resident_warps;
      sampled_mask=t.record.write_mask;
      architectural_commits.sample();
      opcode_seen[sampled_opcode]=1'b1;
      warp_seen[sampled_warp]=1'b1;
      source_seen[sampled_source]=1'b1;
      resident_warps_seen[sampled_resident_warps]=1'b1;
      execute_stall_seen[sampled_execute_stall]=1'b1;
      writeback_stall_seen[sampled_writeback_stall]=1'b1;
      if(sampled_mask==8'h00) mask_class_seen[0]=1'b1;
      else if(sampled_mask==8'hff) mask_class_seen[1]=1'b1;
      else if(sampled_mask inside {8'h0f,8'hf0}) mask_class_seen[2]=1'b1;
      else mask_class_seen[3]=1'b1;
    endfunction
    function void final_phase(uvm_phase phase);
      int file_handle=$fopen("build/uvm/portable_coverage.txt","w");
      if(!file_handle) begin
        `uvm_error("COVERAGE","cannot write portable coverage manifest")
        return;
      end
      foreach(opcode_seen[index]) if(opcode_seen[index])
        $fdisplay(file_handle,"opcode %0d",index);
      foreach(warp_seen[index]) if(warp_seen[index])
        $fdisplay(file_handle,"warp %0d",index);
      foreach(source_seen[index]) if(source_seen[index])
        $fdisplay(file_handle,"source %0d",index);
      foreach(resident_warps_seen[index]) if(resident_warps_seen[index])
        $fdisplay(file_handle,"resident_warps %0d",index);
      foreach(mask_class_seen[index]) if(mask_class_seen[index])
        $fdisplay(file_handle,"mask_class %0d",index);
      foreach(execute_stall_seen[index]) if(execute_stall_seen[index])
        $fdisplay(file_handle,"execute_stall %0d",index);
      foreach(writeback_stall_seen[index]) if(writeback_stall_seen[index])
        $fdisplay(file_handle,"writeback_stall %0d",index);
      $fclose(file_handle);
    endfunction
  endclass

  class differential_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(differential_scoreboard)
    uvm_analysis_imp #(commit_item,differential_scoreboard) analysis_export;
    int trace_file, observed;
    int expected_sequence[int];
    int unsigned expected_warps=4;
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
      if(expected_sequence.num()!=expected_warps)
        `uvm_error("WARP_COUNT",$sformatf("observed warps=%0d expected=%0d",
                   expected_sequence.num(),expected_warps))
      foreach(expected_sequence[warp])
        if(expected_sequence[warp]!=(observed/expected_warps))
          `uvm_error("WARP_COUNT",$sformatf("warp=%0d commits=%0d expected=%0d",
                     warp,expected_sequence[warp],observed/expected_warps))
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

  class memory_differential_test extends uvm_test;
    `uvm_component_utils(memory_differential_test)
    core_env env;virtual simt_core_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);env=core_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","test requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      memory_sequence test_sequence=memory_sequence::type_id::create("test_sequence");
      phase.raise_objection(this);test_sequence.start(env.agent.sequencer);
      repeat(2000)begin @(negedge vif.clk);if(vif.done||vif.fault)break;end
      if(!vif.done||vif.fault)`uvm_error("MEMORY","memory kernel failed")
      if(vif.issue_count!=28||vif.commit_count!=28)
        `uvm_error("COUNTERS",$sformatf("issue=%0d commit=%0d",
          vif.issue_count,vif.commit_count))
      `uvm_info("MEMORY","general/shared memory trace completed",UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class backpressure_differential_test extends uvm_test;
    `uvm_component_utils(backpressure_differential_test)
    core_env env;virtual simt_core_if vif;
    int unsigned execute_stall_cycles,writeback_stall_cycles;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);env=core_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","test requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      arithmetic_sequence test_sequence=
        arithmetic_sequence::type_id::create("test_sequence");
      phase.raise_objection(this);
      test_sequence.start(env.agent.sequencer);
      fork
        begin
          repeat(1200) begin
            @(negedge vif.clk);
            if(vif.done||vif.fault) break;
            if(vif.running) begin
              vif.execute_completion_ready=($urandom_range(0,3)!=0);
              vif.commit_ready=($urandom_range(0,2)!=0);
              if(!vif.execute_completion_ready) execute_stall_cycles++;
              if(!vif.commit_ready) writeback_stall_cycles++;
            end
          end
          vif.execute_completion_ready=1'b1;
          vif.commit_ready=1'b1;
        end
      join
      if(!vif.done) `uvm_error("TIMEOUT","backpressure kernel did not drain")
      if(vif.fault) `uvm_error("FAULT","backpressure kernel faulted")
      if(execute_stall_cycles==0||writeback_stall_cycles==0)
        `uvm_error("STALL_COVERAGE","random test did not inject both stall types")
      if(vif.issue_count!=24||vif.commit_count!=24)
        `uvm_error("COUNTERS",$sformatf("issue=%0d commit=%0d",
                   vif.issue_count,vif.commit_count))
      `uvm_info("BACKPRESSURE",$sformatf("execute_stalls=%0d writeback_stalls=%0d",
                execute_stall_cycles,writeback_stall_cycles),UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class structured_control_differential_test extends uvm_test;
    `uvm_component_utils(structured_control_differential_test)
    core_env env;virtual simt_core_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);env=core_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","test requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      structured_control_sequence test_sequence=
        structured_control_sequence::type_id::create("test_sequence");
      int warp_override,nested_override;
      phase.raise_objection(this);
      if(!test_sequence.randomize())
        `uvm_fatal("RANDOMIZE","structured-control randomization failed")
      if($value$plusargs("WARP_COUNT=%d",warp_override)&&warp_override!=0) begin
        if(warp_override<1||warp_override>4)
          `uvm_fatal("CONFIG","WARP_COUNT must be 1..4")
        test_sequence.warp_count=3'(warp_override);
      end
      if($value$plusargs("NESTED=%d",nested_override)&&nested_override<=1)
        test_sequence.nested=1'(nested_override);
      env.scoreboard.expected_warps=test_sequence.warp_count;
      test_sequence.start(env.agent.sequencer);
      repeat(2000) begin @(negedge vif.clk); if(vif.done||vif.fault) break; end
      if(!vif.done) `uvm_error("TIMEOUT","structured-control kernel did not drain")
      if(vif.fault) `uvm_error("FAULT","structured-control kernel faulted")
      if(vif.issue_count!=64'(test_sequence.instruction_count*test_sequence.warp_count)||
         vif.commit_count!=64'(test_sequence.instruction_count*test_sequence.warp_count))
        `uvm_error("COUNTERS",$sformatf("nested=%0d warps=%0d issue=%0d commit=%0d",
          test_sequence.nested,test_sequence.warp_count,
          vif.issue_count,vif.commit_count))
      `uvm_info("STRUCTURED_CONTROL",$sformatf("nested=%0d warps=%0d commits=%0d",
                test_sequence.nested,test_sequence.warp_count,
                vif.commit_count),UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class isa_coverage_differential_test extends uvm_test;
    `uvm_component_utils(isa_coverage_differential_test)
    core_env env;virtual simt_core_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);env=core_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","test requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      isa_coverage_sequence test_sequence=
        isa_coverage_sequence::type_id::create("test_sequence");
      int warp_override;
      phase.raise_objection(this);
      if($value$plusargs("WARP_COUNT=%d",warp_override)&&warp_override!=0)
        test_sequence.warp_count=warp_override;
      if(test_sequence.warp_count<1||test_sequence.warp_count>4)
        `uvm_fatal("CONFIG","WARP_COUNT must be 1..4")
      env.scoreboard.expected_warps=test_sequence.warp_count;
      test_sequence.start(env.agent.sequencer);
      repeat(3000) begin @(negedge vif.clk);if(vif.done||vif.fault)break;end
      if(!vif.done||vif.fault) `uvm_error("ISA_COVERAGE","kernel failed")
      if(vif.commit_count!=64'(test_sequence.instruction_count*test_sequence.warp_count))
        `uvm_error("COUNTERS",$sformatf("instructions=%0d warps=%0d commits=%0d",
          test_sequence.instruction_count,test_sequence.warp_count,vif.commit_count))
      `uvm_info("ISA_COVERAGE",$sformatf("warps=%0d commits=%0d",
                test_sequence.warp_count,vif.commit_count),UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class fault_clear_relaunch_differential_test extends uvm_test;
    `uvm_component_utils(fault_clear_relaunch_differential_test)
    core_env env;virtual simt_core_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);env=core_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","test requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      stack_underflow_sequence fault_sequence=
        stack_underflow_sequence::type_id::create("fault_sequence");
      core_clear_sequence clear_sequence=
        core_clear_sequence::type_id::create("clear_sequence");
      arithmetic_sequence recovery_sequence=
        arithmetic_sequence::type_id::create("recovery_sequence");
      phase.raise_objection(this);
      env.agent.monitor.allow_expected_fault=1'b1;
      env.agent.monitor.expected_fault_code=FAULT_SIMT_STACK_UNDERFLOW;
      fault_sequence.start(env.agent.sequencer);
      repeat(100) begin @(negedge vif.clk); if(vif.fault) break; end
      if(!vif.fault||vif.fault_code!=FAULT_SIMT_STACK_UNDERFLOW||vif.fault_pc!=0)
        `uvm_error("FAULT","expected stack-underflow fault was not observed")
      if(vif.issue_count!=0||vif.commit_count!=0||vif.commit_valid)
        `uvm_error("FAULT_SIDE_EFFECT",$sformatf("issue=%0d commit=%0d valid=%0d",
          vif.issue_count,vif.commit_count,vif.commit_valid))
      clear_sequence.start(env.agent.sequencer);
      repeat(10) begin @(negedge vif.clk); if(!vif.fault) break; end
      if(vif.fault) `uvm_error("RECOVERY","clear did not remove sticky fault")
      recovery_sequence.initial_epoch=1;
      recovery_sequence.start(env.agent.sequencer);
      repeat(500) begin @(negedge vif.clk); if(vif.done||vif.fault) break; end
      if(!vif.done||vif.fault) `uvm_error("RECOVERY","recovery kernel failed")
      if(vif.issue_count!=24||vif.commit_count!=24)
        `uvm_error("COUNTERS",$sformatf("issue=%0d commit=%0d",
                   vif.issue_count,vif.commit_count))
      if(!env.agent.monitor.expected_fault_observed)
        `uvm_error("FAULT_COVERAGE","monitor missed expected fault")
      `uvm_info("FAULT_RECOVERY","stack underflow suppressed and epoch-1 relaunch drained",UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class midflight_clear_relaunch_differential_test extends uvm_test;
    `uvm_component_utils(midflight_clear_relaunch_differential_test)
    core_env env;virtual simt_core_if vif;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);env=core_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","test requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      arithmetic_sequence cancelled_sequence=
        arithmetic_sequence::type_id::create("cancelled_sequence");
      core_clear_sequence clear_sequence=
        core_clear_sequence::type_id::create("clear_sequence");
      arithmetic_sequence recovery_sequence=
        arithmetic_sequence::type_id::create("recovery_sequence");
      int unsigned issue_before_clear;
      phase.raise_objection(this);
      vif.execute_completion_ready=1'b0;
      vif.commit_ready=1'b0;
      cancelled_sequence.start(env.agent.sequencer);
      repeat(100) begin
        @(negedge vif.clk);
        if(vif.issue_count>=3||vif.fault) break;
      end
      issue_before_clear=vif.issue_count;
      if(issue_before_clear<2)
        `uvm_error("CANCEL_SETUP","clear did not encounter outstanding work")
      if(vif.commit_count!=0||vif.commit_valid)
        `uvm_error("CANCEL_SETUP","work committed before cancellation")
      clear_sequence.start(env.agent.sequencer);
      @(negedge vif.clk);
      if(vif.running||vif.done||vif.fault||vif.issue_count!=0||
         vif.commit_count!=0||vif.commit_valid)
        `uvm_error("CANCEL","clear did not atomically quiesce the core")
      vif.execute_completion_ready=1'b1;
      vif.commit_ready=1'b1;
      recovery_sequence.initial_epoch=1;
      recovery_sequence.start(env.agent.sequencer);
      repeat(500) begin @(negedge vif.clk); if(vif.done||vif.fault) break; end
      if(!vif.done||vif.fault) `uvm_error("RECOVERY","recovery kernel failed")
      if(vif.issue_count!=24||vif.commit_count!=24)
        `uvm_error("COUNTERS",$sformatf("issue=%0d commit=%0d",
                   vif.issue_count,vif.commit_count))
      `uvm_info("MIDFLIGHT_CLEAR",$sformatf(
        "cancelled_issues=%0d epoch-1 relaunch commits=%0d",
        issue_before_clear,vif.commit_count),UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass

  class fetch_backpressure_differential_test extends uvm_test;
    `uvm_component_utils(fetch_backpressure_differential_test)
    core_env env;virtual simt_core_if vif;
    int unsigned fetch_stall_cycles;
    function new(string name,uvm_component parent);super.new(name,parent);endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);env=core_env::type_id::create("env",this);
      if(!uvm_config_db#(virtual simt_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NOVIF","test requires simt_core_if")
    endfunction
    task run_phase(uvm_phase phase);
      arithmetic_sequence test_sequence=
        arithmetic_sequence::type_id::create("test_sequence");
      phase.raise_objection(this);
      test_sequence.start(env.agent.sequencer);
      repeat(1000) begin
        @(negedge vif.clk);
        if(vif.done||vif.fault) break;
        if(vif.running) begin
          vif.fetch_response_ready=($urandom_range(0,2)!=0);
          if(!vif.fetch_response_ready) fetch_stall_cycles++;
        end
      end
      vif.fetch_response_ready=1'b1;
      if(!vif.done) `uvm_error("TIMEOUT","fetch-stalled kernel did not drain")
      if(vif.fault) `uvm_error("FAULT","fetch-stalled kernel faulted")
      if(fetch_stall_cycles==0)
        `uvm_error("STALL_COVERAGE","no fetch response stalls were injected")
      if(vif.issue_count!=24||vif.commit_count!=24)
        `uvm_error("COUNTERS",$sformatf("issue=%0d commit=%0d",
                   vif.issue_count,vif.commit_count))
      `uvm_info("FETCH_BACKPRESSURE",$sformatf("stall_cycles=%0d",
                fetch_stall_cycles),UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass
endpackage
