CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round20: src/topology.cpp tests/test_round20.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round20.cpp -o $@
test: test_round20
	./test_round20
clean:
	rm -f test_round20
