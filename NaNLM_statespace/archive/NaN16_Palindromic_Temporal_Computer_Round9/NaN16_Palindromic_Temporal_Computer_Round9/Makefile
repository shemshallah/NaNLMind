CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test clean
test_round9: src/topology.cpp tests/test_round9.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round9.cpp -o $@
test: test_round9
	./test_round9
clean:
	rm -f test_round9
