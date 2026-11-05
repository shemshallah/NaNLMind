CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round22: src/topology.cpp tests/test_round22.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round22.cpp -o $@
test: test_round22
	./test_round22
clean:
	rm -f test_round22
