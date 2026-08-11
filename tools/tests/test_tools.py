import pathlib, struct, sys, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools'),str(ROOT/'tools/assembler'),str(ROOT/'tools/disassembler')]
from assembler import assemble
from disassembler import disassemble_word
from gen_isa_sv import generate as generate_sv
from isa import ISAError
from hex_words_to_bin import convert
class ToolTests(unittest.TestCase):
 def test_all_programs_assemble(self):
  for p in (ROOT/'tb/programs').glob('*.s'): self.assertTrue(assemble(p.read_text(),str(p)))
 def test_round_trip_equivalence(self):
  source='@!P2 ADD R1, R2, R3\nLD.G R4, [R5-4]\nMOVI R6, -9\nEXIT\n'
  words=assemble(source); text='\n'.join(disassemble_word(w).split('  ')[-1] for w in words)
  self.assertEqual(words,assemble(text))
 def test_labels(self): self.assertEqual(len(assemble('BRA done\nNOP\ndone: EXIT')),3)
 def test_useful_diagnostics(self):
  with self.assertRaisesRegex(ISAError,'R0..R15'): assemble('ADD R16, R1, R2','bad.s')
 def test_reserved_opcode_disassembles_word(self): self.assertEqual(disassemble_word(0xfc000000),'.word 0xfc000000')
 def test_sync_round_trip(self): self.assertEqual(assemble(disassemble_word(assemble('SYNC')[0])),assemble('SYNC'))
 def test_immediate_boundaries(self):
  self.assertEqual(len(assemble('MOVI R0, -512\nMOVI R15, 511')),2)
  with self.assertRaisesRegex(ISAError,'does not fit'): assemble('MOVI R0, 512')
 def test_duplicate_label_diagnostic(self):
  with self.assertRaisesRegex(ISAError,'duplicate label'): assemble('x: NOP\nx: EXIT','dup.s')
 def test_generated_sv_contains_canonical_opcodes(self):
  generated=generate_sv(ROOT/'isa/isa.json')
  self.assertIn('OP_ADD = 6\'d1',generated)
  self.assertIn('OP_SYNC = 6\'d31',generated)
  self.assertIn('SR_ARGBASE = 10\'d6',generated)
 def test_hex_word_conversion(self):
  with tempfile.TemporaryDirectory() as directory:
   source=pathlib.Path(directory)/'program.hex';binary=pathlib.Path(directory)/'program.bin'
   source.write_text('38040007\n# comment\n78000000\n')
   self.assertEqual(convert(source,binary),2)
   self.assertEqual(struct.unpack('<2I',binary.read_bytes()),(0x38040007,0x78000000))
if __name__=='__main__':unittest.main()
