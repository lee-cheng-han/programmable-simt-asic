#include "multi_warp_emulator.hpp"

#include <algorithm>
#include <fstream>
#include <iomanip>
#include <stdexcept>

namespace simt {
namespace {
int32_t sx10(uint32_t value) {
  return (value & 0x200) ? int32_t(value | 0xfffffc00u) : int32_t(value);
}
}  // namespace

MultiWarpEmulator::MultiWarpEmulator(unsigned warps) : resident_warps_(warps) {
  if (warps == 0 || warps > kMaxWarps)
    throw std::runtime_error("warp count must be between one and four");
}

void MultiWarpEmulator::load_program(const std::vector<uint32_t>& words) {
  program_ = words;
  epoch_ = 0;
  reset_kernel_state(false);
}

void MultiWarpEmulator::relaunch() {
  epoch_ = uint8_t((epoch_ + 1u) & 0x3fu);
  reset_kernel_state(true);
}

void MultiWarpEmulator::reset_kernel_state(bool preserve_trace) {
  cycle_ = 0;
  issues_ = 0;
  next_warp_ = 0;
  faulted_ = false;
  fault_pc_ = 0;
  barrier_wait_cycles_ = 0;
  multiplies_.clear();
  if (!preserve_trace) trace_.clear();
  warps_ = {};
  for (unsigned warp = 0; warp < kMaxWarps; ++warp) {
    warps_[warp].valid = warp < resident_warps_;
    warps_[warp].active = 0xff;
  }
}

bool MultiWarpEmulator::canonical(uint32_t word, Opcode opcode) const {
  const uint32_t pe = (word >> 25) & 1, inv = (word >> 24) & 1;
  const uint32_t pred = (word >> 22) & 3, rd = (word >> 18) & 15;
  const uint32_t ra = (word >> 14) & 15, rb = (word >> 10) & 15;
  const uint32_t imm = word & 1023;
  if (!pe && (inv || pred)) return false;
  switch (opcode) {
    case Opcode::NOP: case Opcode::BAR: case Opcode::EXIT:
      return !(rd || ra || rb || imm);
    case Opcode::SYNC: return !pe && !(rd || ra || rb || imm);
    case Opcode::ADD: case Opcode::SUB: case Opcode::MUL:
    case Opcode::MIN: case Opcode::MAX: case Opcode::AND: case Opcode::OR:
    case Opcode::XOR: case Opcode::SHL: case Opcode::SHR: case Opcode::SAR:
    case Opcode::SEL: return imm == 0;
    case Opcode::NOT: case Opcode::MOV: return !(rb || imm);
    case Opcode::MOVI: return !(ra || rb);
    case Opcode::SETP_EQ: case Opcode::SETP_NE: case Opcode::SETP_LT:
    case Opcode::SETP_LE: case Opcode::SETP_GT: case Opcode::SETP_GE:
      return rd < 4 && imm == 0;
    case Opcode::LD_G: case Opcode::LD_S: return rb == 0;
    case Opcode::ST_G: case Opcode::ST_S: return rd == 0;
    case Opcode::BRA: return !(rd || ra || rb);
    case Opcode::SSY: return !pe && !(rd || ra || rb);
    case Opcode::S2R: return !(ra || rb) && imm <= 6;
  }
  return false;
}

bool MultiWarpEmulator::eligible(unsigned index) const {
  const auto& warp = warps_[index];
  if (!warp.valid || warp.barrier_wait || warp.pc >= program_.size()) return false;
  const uint32_t word = program_[warp.pc];
  const uint32_t code = word >> 26;
  if (code > 31 || !canonical(word, Opcode(code))) return true;
  const auto opcode = Opcode(code);
  const unsigned rd = (word >> 18) & 15, ra = (word >> 14) & 15;
  const unsigned rb = (word >> 10) & 15;
  bool uses_ra = false, uses_rb = false, writes_gpr = false;
  switch (opcode) {
    case Opcode::ADD: case Opcode::SUB: case Opcode::MUL:
    case Opcode::MIN: case Opcode::MAX: case Opcode::AND: case Opcode::OR:
    case Opcode::XOR: case Opcode::SHL: case Opcode::SHR: case Opcode::SAR:
    case Opcode::SEL: uses_ra = uses_rb = writes_gpr = true; break;
    case Opcode::NOT: case Opcode::MOV: uses_ra = writes_gpr = true; break;
    case Opcode::MOVI: case Opcode::S2R: writes_gpr = true; break;
    case Opcode::SETP_EQ: case Opcode::SETP_NE: case Opcode::SETP_LT:
    case Opcode::SETP_LE: case Opcode::SETP_GT: case Opcode::SETP_GE:
      uses_ra = uses_rb = true; break;
    case Opcode::LD_G: case Opcode::LD_S: uses_ra = writes_gpr = true; break;
    case Opcode::ST_G: case Opcode::ST_S: uses_ra = uses_rb = true; break;
    default: break;
  }
  return !(uses_ra && warp.gpr_pending[ra]) &&
         !(uses_rb && warp.gpr_pending[rb]) &&
         !(writes_gpr && warp.gpr_pending[rd]);
}

void MultiWarpEmulator::fault(uint32_t pc) {
  faulted_ = true;
  fault_pc_ = pc;
}

void MultiWarpEmulator::commit_event(const TraceEvent& event) {
  auto& warp = warps_[event.warp];
  if (event.writes_gpr) {
    for (unsigned lane = 0; lane < kLanes; ++lane)
      if (event.gpr_mask & (1u << lane))
        warp.registers[event.destination][lane] = event.gpr_data[lane];
    warp.gpr_pending[event.destination] = false;
  }
  if (event.writes_pred) {
    auto& predicate = warp.predicates[event.destination & 3];
    predicate = Mask((predicate & ~event.pred_mask) |
                     (event.pred_data & event.pred_mask));
  }
  trace_.push_back(event);
}

bool MultiWarpEmulator::execute(unsigned index) {
  auto& warp = warps_[index];
  if (warp.pc >= program_.size()) { fault(warp.pc); return false; }
  const uint32_t word = program_[warp.pc], code = word >> 26;
  if (code > 31 || !canonical(word, Opcode(code))) {
    fault(warp.pc); return false;
  }
  const auto opcode = Opcode(code);
  const uint32_t old_pc = warp.pc++;
  const unsigned rd = (word >> 18) & 15, ra = (word >> 14) & 15;
  const unsigned rb = (word >> 10) & 15, pred = (word >> 22) & 3;
  const int32_t imm = sx10(word & 1023);
  const bool pred_enable = (word >> 25) & 1, invert = (word >> 24) & 1;
  Mask execute_mask = warp.active;
  if (pred_enable && opcode != Opcode::SEL)
    execute_mask &= invert ? Mask(~warp.predicates[pred])
                           : warp.predicates[pred];

  TraceEvent event{};
  event.epoch = epoch_;
  event.warp = index;
  event.sequence = warp.sequence++;
  event.pc = old_pc;
  event.instruction = word;
  event.active = warp.active;
  event.write_mask = execute_mask;
  event.destination = uint8_t(rd);
  auto each = [&](auto function) {
    for (unsigned lane = 0; lane < kLanes; ++lane)
      if (execute_mask & (1u << lane)) function(lane);
  };
  auto binary = [&](auto function) {
    event.writes_gpr = true;
    event.gpr_mask = execute_mask;
    each([&](unsigned lane) {
      event.gpr_data[lane] =
        function(warp.registers[ra][lane], warp.registers[rb][lane]);
    });
  };

  switch (opcode) {
    case Opcode::NOP: break;
    case Opcode::ADD: binary([](auto a, auto b) { return a + b; }); break;
    case Opcode::SUB: binary([](auto a, auto b) { return a - b; }); break;
    case Opcode::MUL:
      binary([](auto a, auto b) { return a * b; });
      warp.gpr_pending[rd] = true;
      multiplies_.push_back({cycle_ + 3, event});
      return true;
    case Opcode::MIN: binary([](auto a, auto b) {
      return uint32_t(std::min(int32_t(a), int32_t(b))); }); break;
    case Opcode::MAX: binary([](auto a, auto b) {
      return uint32_t(std::max(int32_t(a), int32_t(b))); }); break;
    case Opcode::AND: binary([](auto a, auto b) { return a & b; }); break;
    case Opcode::OR: binary([](auto a, auto b) { return a | b; }); break;
    case Opcode::XOR: binary([](auto a, auto b) { return a ^ b; }); break;
    case Opcode::NOT:
      event.writes_gpr = true; event.gpr_mask = execute_mask;
      each([&](auto lane) { event.gpr_data[lane] = ~warp.registers[ra][lane]; });
      break;
    case Opcode::SHL: binary([](auto a, auto b) { return a << (b & 31); }); break;
    case Opcode::SHR: binary([](auto a, auto b) { return a >> (b & 31); }); break;
    case Opcode::SAR: binary([](auto a, auto b) {
      return uint32_t(int32_t(a) >> (b & 31)); }); break;
    case Opcode::MOV:
      event.writes_gpr = true; event.gpr_mask = execute_mask;
      each([&](auto lane) { event.gpr_data[lane] = warp.registers[ra][lane]; });
      break;
    case Opcode::MOVI:
      event.writes_gpr = true; event.gpr_mask = execute_mask;
      each([&](auto lane) { event.gpr_data[lane] = uint32_t(imm); });
      break;
    case Opcode::SEL:
      event.writes_gpr = true; event.gpr_mask = execute_mask;
      each([&](auto lane) {
        const bool select_a = ((warp.predicates[pred] >> lane) & 1) != invert;
        event.gpr_data[lane] = warp.registers[select_a ? ra : rb][lane];
      });
      break;
    case Opcode::SETP_EQ: case Opcode::SETP_NE: case Opcode::SETP_LT:
    case Opcode::SETP_LE: case Opcode::SETP_GT: case Opcode::SETP_GE: {
      event.writes_pred = true; event.pred_mask = execute_mask;
      Mask data = warp.predicates[rd & 3];
      each([&](auto lane) {
        const int32_t a = int32_t(warp.registers[ra][lane]);
        const int32_t b = int32_t(warp.registers[rb][lane]);
        const bool result = opcode == Opcode::SETP_EQ ? a == b :
          opcode == Opcode::SETP_NE ? a != b :
          opcode == Opcode::SETP_LT ? a < b :
          opcode == Opcode::SETP_LE ? a <= b :
          opcode == Opcode::SETP_GT ? a > b : a >= b;
        data = result ? Mask(data | (1u << lane))
                      : Mask(data & ~(1u << lane));
      });
      event.pred_data = data;
      break;
    }
    case Opcode::BRA: {
      Mask taken = execute_mask, not_taken = warp.active & Mask(~execute_mask);
      if (!pred_enable) { taken = warp.active; not_taken = 0; }
      if (taken && not_taken) {
        if (!warp.ssy_valid || warp.stack.empty()) { fault(old_pc); return false; }
        auto& stack = warp.stack.back();
        stack.deferred_pc = warp.pc; stack.deferred_mask = not_taken;
        stack.union_mask = warp.active; stack.deferred = true;
        warp.active = taken; warp.pc = uint32_t(int32_t(warp.pc) + imm);
        warp.ssy_valid = false;
      } else if (taken) warp.pc = uint32_t(int32_t(warp.pc) + imm);
      break;
    }
    case Opcode::SSY:
      if (warp.stack.size() >= kStackDepth) { fault(old_pc); return false; }
      warp.stack.push_back({uint32_t(int32_t(warp.pc) + imm), 0, 0,
                            warp.active, false});
      warp.ssy_valid = true;
      break;
    case Opcode::SYNC:
      if (warp.stack.empty() || warp.stack.back().reconv != old_pc) {
        fault(old_pc); return false;
      }
      if (warp.stack.back().deferred) {
        auto& stack = warp.stack.back();
        warp.pc = stack.deferred_pc; warp.active = stack.deferred_mask;
        stack.deferred = false;
      } else {
        warp.active = warp.stack.back().union_mask;
        warp.stack.pop_back(); warp.ssy_valid = false;
      }
      break;
    case Opcode::S2R:
      event.writes_gpr = true; event.gpr_mask = execute_mask;
      each([&](auto lane) {
        switch (word & 1023) {
          case 0: case 3: event.gpr_data[lane] = lane; break;
          case 1: event.gpr_data[lane] = index; break;
          case 5: event.gpr_data[lane] = kLanes; break;
          default: event.gpr_data[lane] = 0; break;
        }
      });
      break;
    case Opcode::EXIT:
      warp.active &= Mask(~execute_mask);
      if (!warp.active && warp.stack.empty()) warp.valid = false;
      break;
    case Opcode::LD_G: case Opcode::LD_S:
    case Opcode::ST_G: case Opcode::ST_S: {
      const bool shared = opcode == Opcode::LD_S || opcode == Opcode::ST_S;
      const bool store = opcode == Opcode::ST_G || opcode == Opcode::ST_S;
      auto* memory = shared ? shared_memory_.data() : scratchpad_.data();
      const size_t memory_size = shared ? shared_memory_.size() : scratchpad_.size();
      std::array<uint32_t, kLanes> addresses{};
      bool invalid = false;
      each([&](unsigned lane) {
        addresses[lane] = warp.registers[ra][lane] + uint32_t(imm);
        invalid |= (addresses[lane] & 3u) != 0 ||
                   addresses[lane] > memory_size - 4;
      });
      if (invalid) { fault(old_pc); return false; }
      if (!store) { event.writes_gpr = true; event.gpr_mask = execute_mask; }
      each([&](unsigned lane) {
        const auto address = addresses[lane];
        if (store) {
          const auto value = warp.registers[rb][lane];
          for (unsigned byte = 0; byte < 4; ++byte)
            memory[address + byte] = uint8_t(value >> (byte * 8));
        } else {
          uint32_t value = 0;
          for (unsigned byte = 0; byte < 4; ++byte)
            value |= uint32_t(memory[address + byte]) << (byte * 8);
          event.gpr_data[lane] = value;
        }
      });
      break;
    }
    case Opcode::BAR:
      if (pred_enable || warp.active != 0xff) {
        fault(old_pc); return false;
      }
      warp.barrier_wait = true;
      warp.barrier_pc = old_pc;
      break;
  }
  commit_event(event);
  return true;
}

bool MultiWarpEmulator::run(uint64_t max_cycles) {
  while (!faulted_ && cycle_ < max_cycles) {
    while (!multiplies_.empty() && multiplies_.front().ready_cycle <= cycle_) {
      commit_event(multiplies_.front().event);
      multiplies_.pop_front();
    }
    bool any_valid = false;
    for (unsigned warp = 0; warp < resident_warps_; ++warp)
      any_valid |= warps_[warp].valid;
    if (!any_valid && multiplies_.empty()) return true;

    bool issued = false;
    for (unsigned offset = 0; offset < resident_warps_; ++offset) {
      const unsigned warp = (next_warp_ + offset) % resident_warps_;
      if (!eligible(warp)) continue;
      issued = execute(warp);
      if (issued) {
        ++issues_;
        next_warp_ = (warp + 1) % resident_warps_;
        bool release_barrier = true;
        for (unsigned resident = 0; resident < resident_warps_; ++resident)
          release_barrier &= warps_[resident].barrier_wait;
        if (release_barrier)
          for (unsigned resident = 0; resident < resident_warps_; ++resident)
            warps_[resident].barrier_wait = false;
        if (release_barrier) barrier_wait_cycles_ = 0;
      }
      break;
    }
    bool any_barrier_wait = false;
    uint32_t first_barrier_pc = 0;
    for (unsigned warp = 0; warp < resident_warps_; ++warp) {
      if (!warps_[warp].barrier_wait) continue;
      if (!any_barrier_wait) first_barrier_pc = warps_[warp].barrier_pc;
      any_barrier_wait = true;
    }
    if (any_barrier_wait) {
      if (++barrier_wait_cycles_ >= 256) fault(first_barrier_pc);
    } else {
      barrier_wait_cycles_ = 0;
    }
    ++cycle_;
  }
  return false;
}

void MultiWarpEmulator::dump_trace(const std::string& path) const {
  std::ofstream file(path);
  if (!file) throw std::runtime_error("cannot open trace: " + path);
  for (const auto& event : trace_) {
    file << "C " << std::dec << unsigned(event.epoch) << ' ' << event.warp
         << ' ' << event.sequence << ' '
         << std::hex << std::setw(8) << std::setfill('0') << event.pc << ' '
         << std::setw(8) << event.instruction << ' '
         << std::setw(2) << unsigned(event.active) << ' '
         << std::setw(2) << unsigned(event.write_mask) << ' '
         << unsigned(event.writes_gpr) << ' '
         << unsigned(event.writes_gpr ? event.destination : 0)
         << ' ' << std::setw(2) << unsigned(event.gpr_mask);
    for (auto value : event.gpr_data) file << ' ' << std::setw(8) << value;
    file << ' ' << unsigned(event.writes_pred) << ' '
         << unsigned(event.writes_pred ? (event.destination & 3) : 0) << ' '
         << std::setw(2) << unsigned(event.pred_mask) << ' '
         << std::setw(2) << unsigned(event.pred_data) << '\n';
  }
}

}  // namespace simt
