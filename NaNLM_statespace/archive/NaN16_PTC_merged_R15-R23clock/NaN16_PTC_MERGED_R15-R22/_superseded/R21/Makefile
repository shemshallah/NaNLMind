CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round21: src/topology.cpp tests/test_round21.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round21.cpp -o $@
test: test_round21
	./test_round21
clean:
	rm -f test_round21
