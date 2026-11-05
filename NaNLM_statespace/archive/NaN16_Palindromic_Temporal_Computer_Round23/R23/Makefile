CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round23: src/topology.cpp tests/test_round23.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round23.cpp -o $@
test: test_round23
	./test_round23
clean:
	rm -f test_round23
