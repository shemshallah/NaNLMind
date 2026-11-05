CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round18: src/topology.cpp tests/test_round18.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round18.cpp -o $@
test: test_round18
	./test_round18
clean:
	rm -f test_round18
