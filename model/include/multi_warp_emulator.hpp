#pragma once

#include <array>
#include <cstdint>
#include <deque>
#include <string>
#include <vector>

#include "isa_generated.hpp"

namespace simt {

class MultiWarpEmulator {
 public:
  static constexpr unsigned kMaxWarps = 4;

  explicit MultiWarpEmulator(unsigned warps);
  void load_program(const std::vector<uint32_t>& words);
  void relaunch();
  bool run(uint64_t max_cycles = 100000);
  void dump_trace(const std::string& path) const;
  uint64_t cycles() const { return cycle_; }
  uint64_t issues() const { return issues_; }
  uint64_t commits() const { return trace_.size(); }
  bool faulted() const { return faulted_; }
  uint32_t fault_pc() const { return fault_pc_; }

 private:
  using Vec = std::array<uint32_t, kLanes>;
  using Mask = uint8_t;

  struct Stack {
    uint32_t reconv{}, deferred_pc{};
    Mask deferred_mask{}, union_mask{};
    bool deferred{};
  };

  struct Warp {
    std::array<Vec, kRegs> registers{};
    std::array<Mask, kPreds> predicates{};
    std::vector<Stack> stack;
    std::array<bool, kRegs> gpr_pending{};
    uint32_t pc{};
    uint16_t sequence{};
    Mask active{0xff};
    bool valid{true};
    bool ssy_valid{};
  };

  struct TraceEvent {
    uint8_t epoch{};
    unsigned warp{};
    uint16_t sequence{};
    uint32_t pc{}, instruction{};
    Mask active{}, write_mask{};
    bool writes_gpr{}, writes_pred{};
    uint8_t destination{}, gpr_mask{}, pred_mask{}, pred_data{};
    Vec gpr_data{};
  };

  struct Multiply {
    uint64_t ready_cycle{};
    TraceEvent event;
  };

  unsigned resident_warps_{};
  uint8_t epoch_{};
  unsigned next_warp_{};
  uint64_t cycle_{}, issues_{};
  bool faulted_{};
  uint32_t fault_pc_{};
  std::vector<uint32_t> program_;
  std::array<Warp, kMaxWarps> warps_{};
  std::deque<Multiply> multiplies_;
  std::vector<TraceEvent> trace_;

  bool canonical(uint32_t word, Opcode opcode) const;
  bool eligible(unsigned warp) const;
  bool execute(unsigned warp);
  void commit_event(const TraceEvent& event);
  void fault(uint32_t pc);
  void reset_kernel_state(bool preserve_trace);
};

}  // namespace simt
