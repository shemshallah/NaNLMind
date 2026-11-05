CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round7: src/topology.cpp tests/test_round7.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round7.cpp -o $@
test: test_round7
	./test_round7
clean:
	rm -f test_round7
