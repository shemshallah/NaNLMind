CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round8: src/topology.cpp tests/test_round8.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round8.cpp -o $@
test: test_round8
	./test_round8
clean:
	rm -f test_round8
