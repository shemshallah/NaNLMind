CXX ?= c++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude
ROUNDS := 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22
.PHONY: test test-all test18t clean
test_round%: src/topology.cpp tests/test_round%.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round$*.cpp -o $@
test_round18t: src/topology.cpp tests/test_round18t_transposition.cpp include/nan16_ptc.hpp
	$(CXX) $(CXXFLAGS) src/topology.cpp tests/test_round18t_transposition.cpp -o $@
test: test_round22
	./test_round22
test18t: test_round18t
	./test_round18t
test-all: $(addprefix test_round,$(ROUNDS)) test_round18t
	@for r in $(ROUNDS) 18t; do echo "== round $$r"; ./test_round$$r > /tmp/nan16_r$$r.log 2>&1 && echo ok || echo FAIL; tail -n 3 /tmp/nan16_r$$r.log; done
clean:
	rm -f $(addprefix test_round,$(ROUNDS)) test_round18t
