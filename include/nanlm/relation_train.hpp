#pragma once

namespace nanlm {

// N16REL/1 typed relation learner. Updates the shared 256-head topology,
// canonical mirror-pair cells, temporal links and n-ary hypergraph.
int relation_train_cli(int argc, char** argv);
// Read-only relation inference over an existing serialized topology.
int relation_eval_cli(int argc, char** argv);

} // namespace nanlm
