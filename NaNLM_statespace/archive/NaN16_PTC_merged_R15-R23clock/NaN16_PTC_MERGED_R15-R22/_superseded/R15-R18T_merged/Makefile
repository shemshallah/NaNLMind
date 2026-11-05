CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test test18 clean
test_round17: src/topology.cpp tests/test_round17.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round17.cpp -o $@
test: test_round17
	./test_round17
clean:
	rm -f test_round17 test_round18
test_round18: src/topology.cpp tests/test_round18.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round18.cpp -o $@
test18: test_round18
	./test_round18
