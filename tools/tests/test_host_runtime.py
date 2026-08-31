import pathlib, struct, tempfile, unittest
from tools.host.runtime import PlanTransport, SimtRuntime, read_program


class HostRuntimeTest(unittest.TestCase):
    def test_program_loading_and_launch_plan(self):
        bus = PlanTransport(); runtime = SimtRuntime(bus)
        runtime.load_program([0x11223344, 0xAABBCCDD]); runtime.launch(3, 4)
        writes = [op for op in bus.operations if op["operation"] == "write32"]
        self.assertEqual(writes[-3:], [
            {"operation":"write32", "address":8, "value":3},
            {"operation":"write32", "address":12, "value":4},
            {"operation":"write32", "address":0, "value":1}])
        self.assertEqual(writes[1]["value"], 0x11223344)

    def test_program_binary_is_little_endian(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "program.bin"
            path.write_bytes(struct.pack("<2I", 1, 0xFEDCBA98))
            self.assertEqual(read_program(path), [1, 0xFEDCBA98])

    def test_launch_shape_is_checked(self):
        with self.assertRaises(ValueError): SimtRuntime(PlanTransport()).launch(0, 0)


if __name__ == "__main__": unittest.main()
