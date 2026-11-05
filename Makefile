CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
DEPFLAGS := -MMD -MP
LDFLAGS ?=
BUILD := build

LIB_SRC := src/sha256.cpp src/universe.cpp src/pager.cpp src/resonance.cpp src/ledger.cpp src/ring.cpp src/hypergraph.cpp src/temporal.cpp src/global.cpp src/head.cpp src/clock.cpp src/consolidation.cpp src/schedule.cpp src/handoff.cpp src/router.cpp src/frame_sync.cpp src/meta_index.cpp src/atomic.cpp src/ntf.cpp src/ncr.cpp src/training.cpp src/supercluster.cpp src/byte_model.cpp src/slot_memory.cpp
LIB_OBJ := $(patsubst src/%.cpp,$(BUILD)/%.o,$(LIB_SRC))
LIB := $(BUILD)/libnanlm.a
CLI := $(BUILD)/nanlm-universal

TEST_SRC := tests/test_address.cpp tests/test_nan16.cpp tests/test_universe.cpp tests/test_pager.cpp tests/test_resonance.cpp tests/test_ledger.cpp tests/test_scale.cpp tests/test_hypergraph.cpp tests/test_temporal.cpp tests/test_global.cpp tests/test_heads.cpp tests/test_clock.cpp tests/test_phase.cpp tests/test_growth.cpp tests/test_consolidation.cpp tests/test_handoff.cpp tests/test_training.cpp tests/test_r18t_sequence.cpp tests/test_router.cpp tests/test_inverse.cpp tests/test_frame_sync.cpp tests/test_meta_index.cpp tests/test_contemplation.cpp tests/test_atomic.cpp tests/test_ntf.cpp tests/test_ncr.cpp tests/test_universe_task.cpp tests/test_supercluster.cpp tests/test_byte_model.cpp tests/test_recovery.cpp tests/test_slot_model.cpp
TEST_BIN := $(patsubst tests/%.cpp,$(BUILD)/%,$(TEST_SRC))

.PHONY: all test clean verify legacy universe-check

LEGACY_R23 := NaNLM_statespace/archive/NaN16_Palindromic_Temporal_Computer_Round23/R23
LEGACY_BIN := $(BUILD)/test_legacy_logic

all: $(CLI)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: src/%.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) $(DEPFLAGS) -c $< -o $@

$(LIB): $(LIB_OBJ)
	$(AR) rcs $@ $^

$(CLI): $(BUILD)/main.o $(LIB)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS)

$(BUILD)/test_%: tests/test_%.cpp $(LIB) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) -o $@ $(LDFLAGS)

test: $(CLI) $(TEST_BIN)
	@set -e; for t in $(TEST_BIN); do echo "== $$t"; ./$$t; done
	@echo "== CLI verify"; ./$(CLI) verify
	@echo "== CLI genesis"; ./$(CLI) genesis
	@echo "== CLI scale"; ./$(CLI) scale

$(LEGACY_BIN): tests/test_legacy_logic.cpp $(LEGACY_R23)/src/topology.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -I$(LEGACY_R23)/include tests/test_legacy_logic.cpp $(LEGACY_R23)/src/topology.cpp -o $@

legacy: $(LEGACY_BIN)
	./$(LEGACY_BIN)

universe-check: $(BUILD)/test_universe_task $(BUILD)/test_byte_model $(BUILD)/test_slot_model $(BUILD)/test_heads $(BUILD)/test_training $(BUILD)/test_r18t_sequence $(BUILD)/test_handoff $(BUILD)/test_growth $(BUILD)/test_inverse $(BUILD)/test_contemplation $(BUILD)/test_recovery
	@set -e; for t in $^; do ./$$t; done

verify: $(CLI)
	./$(CLI) verify

-include $(LIB_OBJ:.o=.d) $(BUILD)/main.d

clean:
	rm -rf $(BUILD)
