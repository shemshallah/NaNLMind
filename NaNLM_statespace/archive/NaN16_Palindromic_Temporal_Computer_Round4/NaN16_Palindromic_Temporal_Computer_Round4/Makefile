CXX      ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude

.PHONY: all test clean

all: test_round4

test_round4: src/topology.cpp tests/test_round4.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round4.cpp -o $@

test: test_round4
	./test_round4

clean:
	rm -f test_round4
