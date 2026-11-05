CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round16: src/topology.cpp tests/test_round16.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round16.cpp -o $@
test: test_round16
	./test_round16
clean:
	rm -f test_round16
