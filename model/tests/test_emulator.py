import pathlib, subprocess, sys, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0,str(ROOT/'tools/assembler'))
from assembler import assemble
class EmulatorTests(unittest.TestCase):
 def run_program(self,name,memory=None,ok=True):
  import struct
  with tempfile.TemporaryDirectory() as d:
   b=pathlib.Path(d)/'p.bin'; state=pathlib.Path(d)/'state.txt'; ws=assemble((ROOT/'tb/programs'/name).read_text(),name); b.write_bytes(struct.pack('<%dI'%len(ws),*ws))
   cmd=[str(ROOT/'build/simt-emulator'),str(b),'--dump',str(state)]
   if memory:cmd += ['--memory',str(ROOT/'tb/programs'/memory)]
   r=subprocess.run(cmd,text=True,capture_output=True); self.assertEqual(r.returncode,0 if ok else 1,r.stdout+r.stderr); return state.read_text(),r.stdout
 def test_arithmetic(self):
  s,_=self.run_program('arithmetic.s'); self.assertIn('R3=0000000a',s);self.assertIn('R4=0000001e',s)
 def test_predication(self):
  s,_=self.run_program('predication.s');self.assertIn('LANE 0',s);self.assertIn('R3=00000001',s.splitlines()[3]);self.assertIn('R3=00000002',s.splitlines()[7])
 def test_select_uses_predicate_without_masking_write(self):
  s,_=self.run_program('select.s')
  lanes=[line for line in s.splitlines() if line.startswith('LANE ')]
  for lane in lanes[:4]: self.assertIn('R4=0000000b',lane)
  for lane in lanes[4:]: self.assertIn('R4=00000016',lane)
 def test_branch(self):
  s,_=self.run_program('branch.s');self.assertIn('R3=00000005',s)
 def test_divergence_and_reconvergence(self):
  s,_=self.run_program('divergence.s')
  lanes=[line for line in s.splitlines() if line.startswith('LANE ')]
  for lane in lanes[:4]: self.assertIn('R3=00000005',lane)
  for lane in lanes[4:]: self.assertIn('R3=00000009',lane)
 def test_global_memory(self):
  s,_=self.run_program('global_memory.s');self.assertIn('R3=0000002a',s);self.assertIn('MEM 80 2a',s)
 def test_vector_add(self):
  s,_=self.run_program('vector_add.s','vector_add.mem');
  for a,v in [(0x40,11),(0x44,22),(0x48,33),(0x4c,44),(0x50,55),(0x54,66),(0x58,77),(0x5c,88)]:self.assertIn(f'MEM {a:x} {v:x}',s)
 def test_illegal_instruction_fault(self):
  s,o=self.run_program('illegal.s',ok=False);self.assertIn('fault=1',o);self.assertIn('FAULT 1',s)
 def test_noncanonical_instruction_fault(self):
  s,o=self.run_program('noncanonical.s',ok=False);self.assertIn('fault=1',o);self.assertIn('PC 0',s)
 def test_stack_underflow_fault(self):
  s,o=self.run_program('stack_underflow.s',ok=False);self.assertIn('fault=6',o);self.assertIn('PC 0',s)
 def test_stack_overflow_fault(self):
  s,o=self.run_program('stack_overflow.s',ok=False);self.assertIn('fault=5',o);self.assertIn('PC 8',s)
 def run_multiwarp(self,name,warps=4,ok=True):
  import struct
  with tempfile.TemporaryDirectory() as d:
   b=pathlib.Path(d)/'p.bin'; trace=pathlib.Path(d)/'trace.txt'
   ws=assemble((ROOT/'tb/programs'/name).read_text(),name)
   b.write_bytes(struct.pack('<%dI'%len(ws),*ws))
   r=subprocess.run([str(ROOT/'build/simt-emulator'),str(b),'--warps',str(warps),
                     '--trace',str(trace)],text=True,capture_output=True)
   self.assertEqual(r.returncode,0 if ok else 1,r.stdout+r.stderr)
   events=[line.split() for line in trace.read_text().splitlines()]
   self.assertTrue(all(event[0]=='C' for event in events))
   keys=[(int(event[1]),int(event[2]),int(event[3])) for event in events]
   self.assertEqual(len(keys),len(set(keys)))
  return events,r.stdout
 def test_four_warp_barrier_deadlock_fault(self):
  events,output=self.run_multiwarp('barrier_deadlock.s',ok=False)
  self.assertEqual(len(events),20)
  self.assertIn('fault=1 fault_pc=5',output)
 def test_explicit_one_warp_uses_canonical_multiwarp_trace(self):
  events,output=self.run_multiwarp('divergence.s',1)
  self.assertEqual(len(events),11)
  self.assertTrue(all(int(event[2])==0 for event in events))
  self.assertIn('issues=11 commits=11 warps=1 runs=1 fault=0',output)
 def test_four_warp_arithmetic_trace(self):
  events,output=self.run_multiwarp('four_warp_arithmetic.s')
  self.assertEqual(len(events),24)
  self.assertIn('issues=24 commits=24 warps=4 runs=1 fault=0',output)
  for warp in range(4):
   warp_events=[event for event in events if int(event[2])==warp]
   self.assertEqual([int(event[3]) for event in warp_events],list(range(6)))
   self.assertTrue(all(int(value,16)==warp for value in warp_events[0][11:19]))
 def test_four_warp_memory_trace(self):
  events,output=self.run_multiwarp('global_memory.s')
  self.assertEqual(len(events),20)
  self.assertIn('issues=20 commits=20 warps=4 runs=1 fault=0',output)
  loads=[event for event in events if int(event[5],16)>>26==22]
  self.assertEqual(len(loads),4)
  for event in loads:self.assertTrue(all(int(value,16)==42 for value in event[11:19]))
 def test_four_warp_barrier_trace(self):
  events,output=self.run_multiwarp('four_warp_barrier.s')
  self.assertEqual(len(events),16)
  self.assertIn('issues=16 commits=16 warps=4 runs=1 fault=0',output)
  barrier_indices=[index for index,event in enumerate(events)
                   if int(event[5],16)>>26==28]
  add_indices=[index for index,event in enumerate(events)
               if int(event[5],16)>>26==1]
  self.assertEqual(len(barrier_indices),4)
  self.assertEqual(len(add_indices),4)
  self.assertLess(max(barrier_indices),min(add_indices))
 def test_shared_memory_reduction_trace(self):
  events,output=self.run_multiwarp('shared_reduction.s')
  self.assertEqual(len(events),68)
  self.assertIn('issues=68 commits=68 warps=4 runs=1 fault=0',output)
  results=[event for event in events if int(event[4],16)==15]
  self.assertEqual(len(results),4)
  for event in results:self.assertTrue(all(int(value,16)==6 for value in event[11:19]))
 def test_four_warp_divergence_trace(self):
  events,output=self.run_multiwarp('divergence.s')
  self.assertEqual(len(events),44)
  self.assertIn('issues=44 commits=44 warps=4 runs=1 fault=0',output)
  for warp in range(4):
   warp_events=[event for event in events if int(event[2])==warp]
   self.assertEqual([int(event[3]) for event in warp_events],list(range(11)))
   masks={int(event[4],16):int(event[10],16) for event in warp_events}
   self.assertEqual(masks[7],0x0f)
   self.assertEqual(masks[5],0xf0)
 def test_four_warp_clear_and_relaunch_epochs(self):
  import struct
  with tempfile.TemporaryDirectory() as d:
   b=pathlib.Path(d)/'p.bin'; trace=pathlib.Path(d)/'trace.txt'
   ws=assemble((ROOT/'tb/programs/four_warp_arithmetic.s').read_text(),'four_warp_arithmetic.s')
   b.write_bytes(struct.pack('<%dI'%len(ws),*ws))
   r=subprocess.run([str(ROOT/'build/simt-emulator'),str(b),'--warps','4',
                     '--runs','2','--trace',str(trace)],text=True,capture_output=True)
   self.assertEqual(r.returncode,0,r.stdout+r.stderr)
   events=[line.split() for line in trace.read_text().splitlines()]
   self.assertEqual(len(events),48)
   self.assertEqual({int(event[1]) for event in events},{0,1})
   for epoch in range(2):
    epoch_events=[event for event in events if int(event[1])==epoch]
    self.assertEqual(len(epoch_events),24)
    self.assertEqual(len({(event[2],event[3]) for event in epoch_events}),24)
if __name__=='__main__':unittest.main()
