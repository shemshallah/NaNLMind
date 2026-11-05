CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round14: src/topology.cpp tests/test_round14.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round14.cpp -o $@
test: test_round14
	./test_round14
clean:
	rm -f test_round14
