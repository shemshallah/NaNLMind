CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round13: src/topology.cpp tests/test_round13.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round13.cpp -o $@
test: test_round13
	./test_round13
clean:
	rm -f test_round13
