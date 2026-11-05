CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round11: src/topology.cpp tests/test_round11.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round11.cpp -o $@
test: test_round11
	./test_round11
clean:
	rm -f test_round11
