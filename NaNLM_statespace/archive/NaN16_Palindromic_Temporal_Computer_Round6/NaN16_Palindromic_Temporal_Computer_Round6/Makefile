CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: all test clean
all: test_round6
test_round6: src/topology.cpp tests/test_round6.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round6.cpp -o $@
test_round5: src/topology.cpp tests/test_round5.cpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round5.cpp -o $@
test: test_round6
	./test_round6
clean:
	rm -f test_round6 test_round5
