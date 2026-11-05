CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
.PHONY: test test_r14 determinism clean
test_round15: src/topology.cpp tests/test_round15.cpp include/nan16_ptc.hpp include/continuity.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round15.cpp -o $@
test: test_round15
	./test_round15
test_r14: src/topology.cpp tests/test_round14.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round14.cpp -o $@ && ./$@
# Same event stream, different compilers/opt levels: the chain head must be bit-identical.
determinism:
	@for O in "-O0" "-O2" "-O3 -march=native" "-O1 -fno-inline"; do \
	  $(CXX) -std=c++20 $$O -Iinclude src/topology.cpp tests/test_round15.cpp -o /tmp/r15_det 2>/dev/null && \
	  printf "%-22s " "$$O" && /tmp/r15_det | grep -m1 CHAIN_HEAD; done
clean:
	rm -f test_round15 test_round14
