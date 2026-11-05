CXX ?= clang++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic

.PHONY: all test clean
all: address_orbits

address_orbits: src/address_orbits.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

test_reference: tests/test_reference.cpp src/address_orbits.cpp
	$(CXX) $(CXXFLAGS) tests/test_reference.cpp -o $@

test: test_reference
	./test_reference

clean:
	rm -f address_orbits test_reference
