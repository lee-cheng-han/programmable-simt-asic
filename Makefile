PYTHON ?= python3
CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Wpedantic -Werror -O2
BUILD := build
PROGRAM ?= tb/programs/arithmetic.s

.PHONY: all test python-test emulator-test rtl-test assemble disassemble xsim-smoke clean
all: $(BUILD)/simt-emulator

$(BUILD):
	mkdir -p $@

$(BUILD)/isa_generated.hpp: isa/isa.json tools/gen_isa_header.py | $(BUILD)
	$(PYTHON) tools/gen_isa_header.py $< $@

$(BUILD)/simt-emulator: model/emulator/main.cpp model/include/emulator.hpp model/emulator/emulator.cpp model/include/multi_warp_emulator.hpp model/emulator/multi_warp_emulator.cpp $(BUILD)/isa_generated.hpp
	$(CXX) $(CXXFLAGS) -I$(BUILD) -Imodel/include model/emulator/main.cpp model/emulator/emulator.cpp model/emulator/multi_warp_emulator.cpp -o $@

python-test:
	$(PYTHON) -m unittest discover -s tools/tests -v

emulator-test: $(BUILD)/simt-emulator
	$(PYTHON) -m unittest discover -s model/tests -v

test: python-test emulator-test rtl-test

rtl-test:
	scripts/run_rtl_unit_tests.sh

assemble: | $(BUILD)
	$(PYTHON) tools/assembler/assembler.py $(PROGRAM) -o $(BUILD)/$(notdir $(basename $(PROGRAM))).bin

disassemble:
	$(PYTHON) tools/disassembler/disassembler.py $(BUILD)/$(notdir $(basename $(PROGRAM))).bin

xsim-smoke:
	scripts/run_xsim_smoke.sh

clean:
	scripts/clean.sh
