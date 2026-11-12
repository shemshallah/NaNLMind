CXX ?= c++
CC ?= cc
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Iinclude -Ithird_party/nan0s/core
NAN0S_CFLAGS ?= -std=gnu99 -O2 -ffp-contract=off -fno-fast-math -Ithird_party/nan0s/core
DEPFLAGS := -MMD -MP
LDFLAGS ?=
LDLIBS ?= -lm
BUILD := build
NAN0S_NMK := third_party/nan0s/tools/nmk.awk
FIELD_DRIVER := $(BUILD)/field_driver.nan
HEAD_WORKER := $(BUILD)/head_worker.nan

LIB_SRC := src/sha256.cpp src/journal_forest.cpp src/universe.cpp src/pager.cpp src/resonance.cpp src/ledger.cpp src/ring.cpp src/hypergraph.cpp src/hypermatrix.cpp src/temporal.cpp src/global.cpp src/head.cpp src/clock.cpp src/consolidation.cpp src/schedule.cpp src/handoff.cpp src/router.cpp src/frame_sync.cpp src/meta_index.cpp src/atomic.cpp src/ntf.cpp src/ncr.cpp src/training.cpp src/supercluster.cpp src/byte_model.cpp src/slot_memory.cpp src/context2.cpp src/context2_topology.cpp src/vector_store.cpp src/word_memory.cpp src/bootstrap_router.cpp src/bootstrap_layers.cpp src/overbootstrap.cpp src/learning_mesh.cpp src/word_vector.cpp src/head_gate.cpp src/boolean_spectrum.cpp src/hypervector.cpp src/reversible.cpp src/semiring.cpp src/sparse_exception.cpp src/two_counter.cpp src/limb_counter.cpp src/two_counter_limb.cpp src/turing_machine.cpp src/universal_tm.cpp src/tm_description.cpp src/tape_checkpoint.cpp src/binary_tm_compiler.cpp src/binary_utm.cpp src/logic_session.cpp src/relation_train.cpp src/head_candidate.cpp src/endpoint_evidence.cpp src/ntt257.cpp src/raw_field.cpp src/sparse_field.cpp src/trunk_train.cpp
LIB_OBJ := $(patsubst src/%.cpp,$(BUILD)/%.o,$(LIB_SRC))
LIB := $(BUILD)/libnanlm.a
NAN0S_SRC := third_party/nan0s/core/nan16.c third_party/nan0s/core/nan_dev.c third_party/nan0s/core/nan_load.c third_party/nan0s/core/nan_net_driver.c third_party/nan0s/core/nan_render.c third_party/nan0s/core/nan_state.c
NAN0S_OBJ := $(patsubst third_party/nan0s/core/%.c,$(BUILD)/nan0s_%.o,$(NAN0S_SRC))
NAN0S_LIB := $(BUILD)/libnan0s.a
CLI := $(BUILD)/nanlm-universal

TEST_SRC := tests/test_journal_forest.cpp tests/test_address.cpp tests/test_nan16.cpp tests/test_volume_address.cpp tests/test_universe.cpp tests/test_pager.cpp tests/test_resonance.cpp tests/test_ledger.cpp tests/test_scale.cpp tests/test_hypergraph.cpp tests/test_hypermatrix.cpp tests/test_temporal.cpp tests/test_global.cpp tests/test_heads.cpp tests/test_clock.cpp tests/test_phase.cpp tests/test_growth.cpp tests/test_consolidation.cpp tests/test_handoff.cpp tests/test_training.cpp tests/test_r18t_sequence.cpp tests/test_router.cpp tests/test_inverse.cpp tests/test_frame_sync.cpp tests/test_meta_index.cpp tests/test_contemplation.cpp tests/test_atomic.cpp tests/test_ntf.cpp tests/test_ncr.cpp tests/test_universe_task.cpp tests/test_supercluster.cpp tests/test_byte_model.cpp tests/test_recovery.cpp tests/test_slot_model.cpp tests/test_kneser_ney.cpp tests/test_context2.cpp tests/test_context2_topology.cpp tests/test_vector_store.cpp tests/test_word_memory.cpp tests/test_bootstrap_router.cpp tests/test_bootstrap_layers.cpp tests/test_overbootstrap_map.cpp tests/test_learning_mesh.cpp tests/test_hyperparameter.cpp tests/test_bit_byte_learning.cpp tests/test_relation_curriculum.cpp tests/test_word_stream_learning.cpp tests/test_word_vector_learning.cpp tests/test_logic_scale.cpp tests/test_boolean_curriculum.cpp tests/test_relation_boolean_gate.cpp tests/test_transform_chain.cpp tests/test_boolean_spectrum.cpp tests/test_hypervector.cpp tests/test_hypervector_scale.cpp tests/test_degree_exceptions.cpp tests/test_sparse_degree_20k.cpp tests/test_two_counter.cpp tests/test_limb_atlas.cpp tests/test_two_counter_limb.cpp tests/test_turing_machine.cpp tests/test_universal_tm.cpp tests/test_utm_proof.cpp tests/test_tape_checkpoint.cpp tests/test_small_utm.cpp tests/test_minsky_utm.cpp tests/test_minsky_encoded.cpp tests/test_utm_universal_desc.cpp tests/test_binary_tm_compiler.cpp tests/test_binary_utm.cpp tests/test_binary_utm_self.cpp tests/test_logic_session.cpp tests/test_relation_train.cpp tests/test_endpoint_evidence.cpp tests/test_two_counter_orbit.cpp tests/test_reversible.cpp tests/test_semiring_inheritance.cpp tests/test_sparse_exceptions.cpp tests/test_semiring.cpp tests/test_ntt257.cpp tests/test_ntt_sequence.cpp tests/test_reversible_vs_stored.cpp tests/test_slot_recovery.cpp tests/test_teacher_gate.cpp tests/test_math_catalog.cpp tests/test_raw_field.cpp tests/test_context_backoff.cpp tests/test_sparse_field.cpp tests/test_raw_contextual.cpp
TEST_BIN := $(patsubst tests/%.cpp,$(BUILD)/%,$(TEST_SRC))

.PHONY: all test dual-head-test clean verify unified-check unified-kernel-audit unified-system-check unified-test-base nan16-test legacy self-sim-probe universe-check bootstrap penguin logic behavior challenge warmup merge-test clocked-head-demo byte-mesh curriculum hyper-scale rawroute-test rss-contract-test sparse-field-test raw-contextual-test phase-ingest-check phase-train-check phase-train-book-check wordlist-corpus wordlist-fetch wordlist-intake-check

LEGACY_R23 := NaNLM_statespace/archive/NaN16_Palindromic_Temporal_Computer_Round23/R23
LEGACY_BIN := $(BUILD)/test_legacy_logic
R14 := NaNLM_statespace/archive/NaN16_Palindromic_Temporal_Computer_Round14/NaN16_Palindromic_Temporal_Computer_Round14
R19 := NaNLM_statespace/archive/NaN16_Palindromic_Temporal_Computer_Round19/NaN16_Palindromic_Temporal_Computer_Round19
R20 := NaNLM_statespace/archive/NaN16_Palindromic_Temporal_Computer_Round20/R20
PENGUIN_BIN := $(BUILD)/test_round14_archive
R19_BIN := $(BUILD)/test_round19_archive
R20_BIN := $(BUILD)/test_round20_archive

all: $(CLI)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: src/%.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) $(DEPFLAGS) -c $< -o $@

$(LIB): $(LIB_OBJ)
	$(AR) rcs $@ $^

$(BUILD)/nan0s_%.o: third_party/nan0s/core/%.c | $(BUILD)
	$(CC) $(NAN0S_CFLAGS) -c $< -o $@

$(NAN0S_LIB): $(NAN0S_OBJ)
	$(AR) rcs $@ $^

$(FIELD_DRIVER): mth/drivers/field_driver.nas $(wildcard mth/nan16/*.nas) $(NAN0S_NMK) | $(BUILD)
	awk -f $(NAN0S_NMK) -v CMD=emit $< > $@.tmp
	@test "$$(wc -l < $@.tmp)" -le 1048576 || { echo "field driver exceeds 0x100000-word guest code/data boundary"; rm -f $@.tmp; exit 1; }
	mv $@.tmp $@

$(HEAD_WORKER): mth/drivers/head_worker.nas $(wildcard mth/nan16/*.nas) $(NAN0S_NMK) | $(BUILD)
	awk -f $(NAN0S_NMK) -v CMD=emit $< > $@.tmp
	@test "$$(wc -l < $@.tmp)" -le 16384 || { echo "head worker overlaps the 0x4000 command block"; rm -f $@.tmp; exit 1; }
	mv $@.tmp $@

$(CLI): $(BUILD)/main.o $(LIB) $(NAN0S_LIB) | $(FIELD_DRIVER)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_%: tests/test_%.cpp $(LIB) $(NAN0S_LIB) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_raw_field: tests/test_raw_field.cpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_dual_head: tests/test_dual_head.cpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_page_arena: tests/test_head_page_arena.cpp include/nanlm/head_page_arena.hpp | $(BUILD)
	$(CXX) $(CXXFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_page_loader: tests/test_head_page_loader.cpp include/nanlm/head_page_loader.hpp include/nanlm/head_page_arena.hpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_block: tests/test_head_block.cpp include/nanlm/head_page_loader.hpp include/nanlm/head_page_arena.hpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_worker: tests/test_head_worker.cpp include/nanlm/head_page_loader.hpp include/nanlm/head_page_arena.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_block64: tests/test_head_block64.cpp include/nanlm/head_page_loader.hpp include/nanlm/head_page_arena.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_worker_scheduler: tests/test_head_worker_scheduler.cpp include/nanlm/head_worker_scheduler.hpp include/nanlm/head_page_loader.hpp include/nanlm/head_page_arena.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_long_context: tests/test_long_context.cpp include/nanlm/long_context_scheduler.hpp include/nanlm/head_worker_scheduler.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_long_context64: tests/test_long_context64.cpp include/nanlm/long_context64_scheduler.hpp include/nanlm/long_context_scheduler.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_chunk_summary: tests/test_chunk_summary.cpp include/nanlm/chunk_summary_scheduler.hpp include/nanlm/chunk_summary.hpp include/nanlm/long_context64_scheduler.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_summary_retrieval: tests/test_summary_retrieval.cpp include/nanlm/summary_retriever.hpp include/nanlm/chunk_summary.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_hierarchical_context: tests/test_hierarchical_context.cpp include/nanlm/long_context64_scheduler.hpp include/nanlm/summary_retriever.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_readout: tests/test_head_readout.cpp include/nanlm/raw_field.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_readout_train: tests/test_head_readout_train.cpp include/nanlm/raw_field.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_page_train: tests/test_head_page_train.cpp include/nanlm/head_page_loader.hpp include/nanlm/head_page_arena.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_head_page_checkpoint: tests/test_head_page_checkpoint.cpp include/nanlm/head_page_checkpoint.hpp include/nanlm/head_page_arena.hpp include/nanlm/sha256.hpp $(LIB) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_nlhe2: tests/test_nlhe2.cpp include/nanlm/nlhe2.hpp include/nanlm/nlhe2_arena.hpp include/nanlm/tensor_point.hpp include/nanlm/tensor_leaf_sidecar.hpp include/nanlm/dual_tensor_arena.hpp | $(BUILD)
	$(CXX) $(CXXFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_dual_tensor_arena: tests/test_dual_tensor_arena.cpp include/nanlm/dual_tensor_arena.hpp | $(BUILD)
	$(CXX) $(CXXFLAGS) $< -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_native48m_feedback: tests/test_native48m_feedback.cpp include/nanlm/native48m_feedback.hpp include/nanlm/dual_tensor_arena.hpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/credit-ablation: tools/credit_ablation.cpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/byte-baselines: tools/nanlm_byte_baselines.cpp $(LIB) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/nanlm48m-native-batch: tools/nanlm48m_native_batch.cpp include/nanlm/raw_field.hpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/nanlm-head-worker-batch: tools/nanlm_head_worker_batch.cpp include/nanlm/head_worker_scheduler.hpp include/nanlm/head_page_loader.hpp include/nanlm/head_page_arena.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/nanlm-head-readout-train: tools/nanlm_head_readout_train.cpp include/nanlm/raw_field.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/nanlm-head-readout-loop: tools/nanlm_head_readout_loop.cpp include/nanlm/raw_field.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/nanlm-head-page-gate: tools/nanlm_head_page_gate.cpp include/nanlm/head_page_checkpoint.hpp include/nanlm/head_page_loader.hpp include/nanlm/raw_field.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/nanlm-head-page-train: tools/nanlm_head_page_train.cpp include/nanlm/head_page_checkpoint.hpp include/nanlm/head_page_loader.hpp include/nanlm/raw_field.hpp $(LIB) $(NAN0S_LIB) $(HEAD_WORKER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/nanlm48m-native-emit: tools/nanlm48m_native_emit.cpp include/nanlm/native48m_feedback_json.hpp include/nanlm/native48m_feedback.hpp include/nanlm/dual_tensor_arena.hpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_native_mirror_triangle_field: tests/test_native_mirror_triangle_field.cpp include/nanlm/native_mirror_triangle_leaf_feedback.hpp include/nanlm/tensor_leaf_sidecar.hpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/nanlm48m-native-future3-measure: tools/nanlm48m_native_future3_measure.cpp include/nanlm/raw_field.hpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_raw_contextual: tests/test_raw_contextual.cpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(BUILD)/test_context_route: tests/test_context_route.cpp $(LIB) $(NAN0S_LIB) $(FIELD_DRIVER) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

test: $(CLI) $(TEST_BIN) $(FIELD_DRIVER)
	@set -e; for t in $(TEST_BIN); do echo "== $$t"; ./$$t; done
	@echo "== CLI verify"; ./$(CLI) verify
	@echo "== CLI genesis"; ./$(CLI) genesis
	@echo "== CLI scale"; ./$(CLI) scale
	@echo "== unified build contract"; python3 tools/unified_build_audit.py
	@echo "== CLI raw field selftest"; ./$(CLI) field-selftest
	@echo "== raw NaN16 adaptive-field fixtures"; python3 tools/run_nan16_fixtures.py

self-sim-probe: $(BUILD)/self_sim_probe
	./$(BUILD)/self_sim_probe 100000000

$(BUILD)/self_sim_probe: experiments/self_sim_probe.cpp $(LIB) $(NAN0S_LIB) | $(BUILD)
	$(CXX) $(CXXFLAGS) -Itests $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

$(LEGACY_BIN): tests/test_legacy_logic.cpp $(LEGACY_R23)/src/topology.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -I$(LEGACY_R23)/include tests/test_legacy_logic.cpp $(LEGACY_R23)/src/topology.cpp -o $@

legacy: $(LEGACY_BIN)
	./$(LEGACY_BIN)

$(PENGUIN_BIN): $(R14)/tests/test_round14.cpp $(R14)/src/topology.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -I$(R14)/include $^ -o $@

penguin: $(PENGUIN_BIN)
	./$(PENGUIN_BIN)

$(R19_BIN): $(R19)/tests/test_round19.cpp $(R19)/src/topology.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -I$(R19)/include $^ -o $@

$(R20_BIN): $(R20)/tests/test_round20.cpp $(R20)/src/topology.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -I$(R20)/include $^ -o $@

logic: $(R19_BIN) $(R20_BIN)
	./$(R19_BIN)
	./$(R20_BIN)

behavior: penguin logic legacy

challenge: $(BUILD)/test_logic_challenge
	./$(BUILD)/test_logic_challenge

universe-check: $(BUILD)/test_universe_task $(BUILD)/test_byte_model $(BUILD)/test_slot_model $(BUILD)/test_kneser_ney $(BUILD)/test_context2 $(BUILD)/test_context2_topology $(BUILD)/test_bootstrap_router $(BUILD)/test_bootstrap_layers $(BUILD)/test_overbootstrap_map $(BUILD)/test_learning_mesh $(BUILD)/test_endpoint_evidence $(BUILD)/test_hyperparameter $(BUILD)/test_bit_byte_learning $(BUILD)/test_relation_curriculum $(BUILD)/test_word_stream_learning $(BUILD)/test_word_vector_learning $(BUILD)/test_logic_scale $(BUILD)/test_boolean_curriculum $(BUILD)/test_relation_boolean_gate $(BUILD)/test_transform_chain $(BUILD)/test_boolean_spectrum $(BUILD)/test_math_catalog $(BUILD)/test_hypervector $(BUILD)/test_teacher_gate $(BUILD)/test_heads $(BUILD)/test_training $(BUILD)/test_r18t_sequence $(BUILD)/test_handoff $(BUILD)/test_growth $(BUILD)/test_inverse $(BUILD)/test_contemplation $(BUILD)/test_recovery
	@set -e; for t in $^; do ./$$t; done

bootstrap: $(CLI)
	./$(CLI) bootstrap data/alice_full.txt 1 8

warmup: $(CLI)
	./$(CLI) warmup 10

$(BUILD)/clocked-demo: integrations/clocked/native_demo.cpp $(LIB) $(NAN0S_LIB) | $(BUILD)
	$(CXX) $(CXXFLAGS) $< $(LIB) $(NAN0S_LIB) -o $@ $(LDFLAGS) $(LDLIBS)

clocked-head-demo: $(BUILD)/clocked-demo
	@echo "Native NaNLMind head demo compiled. Run the CLOCKED service harness from NaNLMind_CLOCKED with --native-binary $(BUILD)/clocked-demo."

rawroute-test:
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_rawroute.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_rawroute_store.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_rawroute_api.py' -v

merge-test:
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_nannet_bridge.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_rawroute.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_rawroute_store.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_rawroute_api.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_nannet_runner_bridge.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_training_merge.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_router_ring_client.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_nannet_runner_ring.py' -v
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_clocked_router_consumer.py' -v
	python3 -m py_compile runner/nanlm_worker.py runner/router_ring_client.py runner/clocked_router_consumer.py
	cd integrations/nannet && python3 -m unittest test_server -v

logic-test:
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_logic*.py' -v

training-test:
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_*pipeline.py' -v

conversation-test:
	PYTHONPATH=runner python3 -m unittest discover -s tests -p 'test_conversation_trainer.py' -v

byte-mesh: $(BUILD)/test_byte_stream_learning
	./$(BUILD)/test_byte_stream_learning

curriculum: $(BUILD)/test_relation_curriculum $(BUILD)/test_word_memory $(BUILD)/test_bit_byte_learning
	./$(BUILD)/test_relation_curriculum
	./$(BUILD)/test_word_memory
	./$(BUILD)/test_bit_byte_learning

hyper-scale: $(BUILD)/test_hypervector_scale
	./$(BUILD)/test_hypervector_scale

verify: $(CLI)
	./$(CLI) verify

unified-check: $(CLI)
	python3 tools/unified_build_audit.py

unified-kernel-audit:
	python3 tools/unified_kernel_audit.py --run

unified-system-check: $(BUILD)/test_raw_field $(BUILD)/test_dual_head
	python3 tools/unified_system_check.py --run

nan16-test:
	python3 tools/run_nan16_fixtures.py

-include $(LIB_OBJ:.o=.d) $(BUILD)/main.d

sparse-field-test: $(BUILD)/test_sparse_field
	./$(BUILD)/test_sparse_field

contextual-test: $(BUILD)/test_contextual_roles $(BUILD)/test_contextual_senses
	./$(BUILD)/test_contextual_roles
	./$(BUILD)/test_contextual_senses

raw-contextual-test: $(BUILD)/test_raw_contextual
	./$(BUILD)/test_raw_contextual

phase-ingest-check: $(CLI)
	./$(CLI) phase-ingest data/alice_excerpt.txt 8 8 64 4
	python3 tools/check_phase_ingest.py

phase-train-check: $(CLI)
	./$(CLI) phase-train data/alice_full.txt 200 8 32 200 state/phase_train
	python3 tools/check_phase_train.py state/phase_train
	./$(CLI) phase-train data/alice_full.txt 200 8 32 200 state/phase_train
	grep -q '"resumed": true' state/phase_train.metrics.json
	python3 tools/check_phase_train.py state/phase_train

phase-train-book-check: $(CLI)
	./$(CLI) phase-train state/gutenberg_150_train.txt 200 8 32 200 state/phase_train_book state/gutenberg_150_heldout.txt
	python3 tools/check_phase_train.py state/phase_train_book

wordlist-corpus:
	python3 tools/prepare_wordlist_corpus.py --root ../NaNROUTER/corpora/wordlists --out state/wordlists.corpus.txt --lower --dedupe

wordlist-fetch:
	tools/fetch_wordlists.sh

wordlist-intake-check: $(CLI)
	python3 tools/check_wordlist_intake.py

clean:
	rm -rf $(BUILD)

sparse-shared-test:
	python3 -m unittest tests.test_sparse_shared


# RSS protocol-envelope tests only; graph/spectral mathematics remains native NaN16 MTH.
rss-contract-test:
	python3 tests/test_relational_spectral_contract.py

dual-head-test: $(BUILD)/test_dual_head
	./$(BUILD)/test_dual_head


unified-test-base: $(CLI) $(FIELD_DRIVER) $(BUILD)/test_raw_field $(BUILD)/test_context_backoff $(BUILD)/test_context_route $(BUILD)/test_native48m_feedback $(BUILD)/test_dual_tensor_arena $(BUILD)/test_head_page_arena $(BUILD)/test_head_page_loader $(BUILD)/test_head_block $(BUILD)/test_head_worker $(BUILD)/test_head_block64 $(BUILD)/test_head_worker_scheduler $(BUILD)/test_long_context $(BUILD)/test_long_context64 $(BUILD)/test_chunk_summary $(BUILD)/test_summary_retrieval $(BUILD)/test_hierarchical_context $(BUILD)/test_head_readout $(BUILD)/test_head_readout_train $(BUILD)/test_head_page_train $(BUILD)/test_head_page_checkpoint $(BUILD)/test_nlhe2 $(BUILD)/credit-ablation $(BUILD)/byte-baselines $(BUILD)/nanlm48m-native-batch $(BUILD)/nanlm-head-worker-batch $(BUILD)/nanlm-head-readout-train $(BUILD)/nanlm-head-readout-loop $(BUILD)/nanlm-head-page-gate $(BUILD)/nanlm-head-page-train
	python3 tools/unified_test_base.py
