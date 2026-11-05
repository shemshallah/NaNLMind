CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_topology: src/topology.cpp tests/test_topology.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_topology.cpp -o $@
test: test_topology
	./test_topology
clean:
	rm -f test_topology
