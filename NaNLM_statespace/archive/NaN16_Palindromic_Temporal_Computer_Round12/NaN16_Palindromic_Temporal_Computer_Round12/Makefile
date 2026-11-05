CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round12: src/topology.cpp tests/test_round12.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round12.cpp -o $@
test: test_round12
	./test_round12
clean:
	rm -f test_round12
