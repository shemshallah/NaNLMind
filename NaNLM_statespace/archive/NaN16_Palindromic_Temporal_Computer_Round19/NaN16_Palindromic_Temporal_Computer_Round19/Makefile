CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round19: src/topology.cpp tests/test_round19.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round19.cpp -o $@
test: test_round19
	./test_round19
clean:
	rm -f test_round19
