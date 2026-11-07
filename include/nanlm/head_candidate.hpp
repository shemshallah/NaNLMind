#pragma once

namespace nanlm {

// Create an isolated, serialized candidate head mutation. The base topology is
// read-only and is never overwritten by this command.
int head_candidate_cli(int argc, char** argv);

} // namespace nanlm
