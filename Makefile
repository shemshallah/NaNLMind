CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
DEPFLAGS := -MMD -MP
LDFLAGS ?=
BUILD := build

LIB_SRC := src/sha256.cpp src/universe.cpp src/pager.cpp src/resonance.cpp src/ledger.cpp src/ring.cpp src/hypergraph.cpp src/temporal.cpp src/global.cpp src/head.cpp src/clock.cpp
LIB_OBJ := $(patsubst src/%.cpp,$(BUILD)/%.o,$(LIB_SRC))
LIB := $(BUILD)/libnanlm.a
CLI := $(BUILD)/nanlm-universal

TEST_SRC := tests/test_address.cpp tests/test_nan16.cpp tests/test_universe.cpp tests/test_pager.cpp tests/test_resonance.cpp tests/test_ledger.cpp tests/test_scale.cpp tests/test_hypergraph.cpp tests/test_temporal.cpp tests/test_global.cpp tests/test_heads.cpp tests/test_clock.cpp
TEST_BIN := $(patsubst tests/%.cpp,$(BUILD)/%,$(TEST_SRC))

.PHONY: all test clean verify

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

verify: $(CLI)
	./$(CLI) verify

-include $(LIB_OBJ:.o=.d) $(BUILD)/main.d

clean:
	rm -rf $(BUILD)
