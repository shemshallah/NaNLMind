// Typed, versioned mathematical operation catalog primitives.
// This is a registry contract and executable Boolean core, not a claim that
// every listed mathematical family has an implementation yet.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <algorithm>
#include <mutex>
#include <optional>
#include <vector>

namespace nanlm {

enum class MathFamily : std::uint8_t {
    Representation, Boolean, Arithmetic, LinearAlgebra, Geometry,
    Relations, DiscreteTransforms, Symbolic, Composition, MetaLearning
};
enum class Exactness : std::uint8_t {
    ExactFinite, ExactInteger, ExactRational, ExactSymbolic,
    BoundedApproximation, Heuristic, LearnedUnverified
};
enum class CatalogStatus : std::uint8_t {
    Implemented, Tested, Verified, Experimental, Planned
};
enum class ValueKind : std::uint8_t {
    Boolean, BitVector, Integer, Rational, Real, Vector, Matrix, Tensor,
    Relation, Graph, Symbolic, Packet
};

struct OperationDescriptor {
    std::string_view id;
    std::string_view name;
    MathFamily family;
    std::uint8_t arity;
    ValueKind input;
    ValueKind output;
    Exactness exactness;
    CatalogStatus status;
    bool deterministic;
    bool side_effect_free;
    // An entry is metadata-only until these proof-bearing contract fields are
    // populated and its status is explicitly Verified.
    std::string_view preconditions = "UNSPECIFIED: not executable";
    std::string_view postconditions = "UNSPECIFIED: not executable";
    std::string_view law_set = "UNSPECIFIED: not executable";
    std::string_view inverse_id = "";
    std::string_view complexity = "UNMEASURED";
};

// Family coverage is explicit. "Planned" is intentionally distinct from
// implemented so the bootstrap learner cannot train against imaginary code.
inline constexpr std::array<OperationDescriptor, 34> kCoreMathCatalog{{
    {"bool.truth2", "two-input Boolean truth-table function", MathFamily::Boolean, 2, ValueKind::Boolean, ValueKind::Boolean, Exactness::ExactFinite, CatalogStatus::Tested, true, true},
    {"bool.compose2", "Boolean function composition", MathFamily::Composition, 2, ValueKind::Boolean, ValueKind::Boolean, Exactness::ExactFinite, CatalogStatus::Planned, true, true},
    {"bool.anf2", "algebraic normal form", MathFamily::Boolean, 1, ValueKind::Boolean, ValueKind::BitVector, Exactness::ExactFinite, CatalogStatus::Tested, true, true},
    {"bool.walsh2", "Walsh spectrum", MathFamily::Boolean, 1, ValueKind::Boolean, ValueKind::Vector, Exactness::ExactInteger, CatalogStatus::Tested, true, true},
    {"integer.add", "integer addition", MathFamily::Arithmetic, 2, ValueKind::Integer, ValueKind::Integer, Exactness::ExactInteger, CatalogStatus::Planned, true, true},
    {"integer.subtract", "integer subtraction", MathFamily::Arithmetic, 2, ValueKind::Integer, ValueKind::Integer, Exactness::ExactInteger, CatalogStatus::Planned, true, true},
    {"integer.multiply", "integer multiplication", MathFamily::Arithmetic, 2, ValueKind::Integer, ValueKind::Integer, Exactness::ExactInteger, CatalogStatus::Planned, true, true},
    {"integer.divide", "integer quotient and remainder", MathFamily::Arithmetic, 2, ValueKind::Integer, ValueKind::Vector, Exactness::ExactInteger, CatalogStatus::Planned, true, true},
    {"vector.dot", "vector inner product", MathFamily::LinearAlgebra, 2, ValueKind::Vector, ValueKind::Integer, Exactness::ExactInteger, CatalogStatus::Planned, true, true},
    {"vector.norm", "vector norm", MathFamily::LinearAlgebra, 1, ValueKind::Vector, ValueKind::Real, Exactness::BoundedApproximation, CatalogStatus::Planned, true, true},
    {"matrix.transpose", "matrix transpose", MathFamily::LinearAlgebra, 1, ValueKind::Matrix, ValueKind::Matrix, Exactness::ExactFinite, CatalogStatus::Planned, true, true},
    {"matrix.multiply", "matrix multiplication", MathFamily::LinearAlgebra, 2, ValueKind::Matrix, ValueKind::Matrix, Exactness::ExactInteger, CatalogStatus::Planned, true, true},
    {"geometry.reflect", "reflection", MathFamily::Geometry, 2, ValueKind::Vector, ValueKind::Vector, Exactness::ExactRational, CatalogStatus::Planned, true, true},
    {"geometry.rotate", "rotation", MathFamily::Geometry, 2, ValueKind::Vector, ValueKind::Vector, Exactness::BoundedApproximation, CatalogStatus::Planned, true, true},
    {"geometry.project", "projection", MathFamily::Geometry, 2, ValueKind::Vector, ValueKind::Vector, Exactness::BoundedApproximation, CatalogStatus::Planned, true, true},
    {"relation.compose", "binary relation composition", MathFamily::Relations, 2, ValueKind::Relation, ValueKind::Relation, Exactness::ExactFinite, CatalogStatus::Planned, true, true},
    {"graph.reachability", "graph reachability", MathFamily::Relations, 1, ValueKind::Graph, ValueKind::Relation, Exactness::ExactFinite, CatalogStatus::Planned, true, true},
    {"transform.permute", "finite permutation", MathFamily::DiscreteTransforms, 2, ValueKind::Vector, ValueKind::Vector, Exactness::ExactFinite, CatalogStatus::Planned, true, true},
    {"transform.walsh", "Walsh-Hadamard transform", MathFamily::DiscreteTransforms, 1, ValueKind::Vector, ValueKind::Vector, Exactness::ExactInteger, CatalogStatus::Planned, true, true},
    {"transform.ntt257", "number theoretic transform modulo 257", MathFamily::DiscreteTransforms, 1, ValueKind::Vector, ValueKind::Vector, Exactness::ExactFinite, CatalogStatus::Tested, true, true},
    {"symbolic.substitute", "symbolic substitution", MathFamily::Symbolic, 2, ValueKind::Symbolic, ValueKind::Symbolic, Exactness::ExactSymbolic, CatalogStatus::Planned, true, true},
    {"proof.check", "proof obligation checker", MathFamily::Symbolic, 1, ValueKind::Symbolic, ValueKind::Boolean, Exactness::ExactSymbolic, CatalogStatus::Planned, true, true},
    {"catalog.compose", "validated operation composition", MathFamily::Composition, 2, ValueKind::Packet, ValueKind::Packet, Exactness::ExactFinite, CatalogStatus::Planned, true, true},
    {"catalog.propose", "head-proposed operation candidate", MathFamily::MetaLearning, 1, ValueKind::Packet, ValueKind::Packet, Exactness::LearnedUnverified, CatalogStatus::Planned, false, true},
    {"matrix256.transpose", "256 by 256 signed matrix transpose", MathFamily::LinearAlgebra, 1, ValueKind::Matrix, ValueKind::Matrix, Exactness::ExactFinite, CatalogStatus::Tested, true, true},
    {"matrix256.symmetric-part", "matrix plus transpose", MathFamily::LinearAlgebra, 1, ValueKind::Matrix, ValueKind::Matrix, Exactness::ExactInteger, CatalogStatus::Tested, true, true},
    {"matrix256.antisymmetric-part", "matrix minus transpose", MathFamily::LinearAlgebra, 1, ValueKind::Matrix, ValueKind::Matrix, Exactness::ExactInteger, CatalogStatus::Tested, true, true},
    {"nan16.transform.forward", "four-NaN Klein-four address transform", MathFamily::Geometry, 2, ValueKind::Integer, ValueKind::Integer, Exactness::ExactFinite, CatalogStatus::Tested, true, true},
    {"nan16.transform.inverse", "inverse four-NaN address transform", MathFamily::Geometry, 2, ValueKind::Integer, ValueKind::Integer, Exactness::ExactFinite, CatalogStatus::Tested, true, true},
    {"coupling16.forward", "reversible 16-bit XOR coupling", MathFamily::DiscreteTransforms, 2, ValueKind::Vector, ValueKind::Vector, Exactness::ExactFinite, CatalogStatus::Tested, true, true},
    {"coupling16.inverse", "inverse reversible 16-bit XOR coupling", MathFamily::DiscreteTransforms, 2, ValueKind::Vector, ValueKind::Vector, Exactness::ExactFinite, CatalogStatus::Tested, true, true},
    {"semiring.boolean.closure256", "256-node Boolean-semiring transitive closure", MathFamily::Relations, 1, ValueKind::Matrix, ValueKind::Matrix, Exactness::ExactFinite, CatalogStatus::Tested, true, true},
    {"ntt257.forward-inverse", "exact 256-point transform over F257", MathFamily::DiscreteTransforms, 1, ValueKind::Vector, ValueKind::Vector, Exactness::ExactFinite, CatalogStatus::Tested, true, true}
}};

constexpr const OperationDescriptor* find_operation(std::string_view id) {
    for (const auto& op : kCoreMathCatalog)
        if (op.id == id) return &op;
    return nullptr;
}

constexpr bool catalog_entry_executable(const OperationDescriptor& op) {
    return op.status == CatalogStatus::Verified &&
           op.preconditions != "UNSPECIFIED: not executable" &&
           op.postconditions != "UNSPECIFIED: not executable" &&
           op.law_set != "UNSPECIFIED: not executable" &&
           op.complexity != "UNMEASURED";
}

// Truth-table bit order follows NaN16: for two variables index = 2*a+b.
// For n variables, variables are supplied most-significant first in the
// index, and arity is limited to 6 so a complete table fits in uint64_t.
constexpr bool valid_boolean_arity(std::uint8_t arity) {
    return arity >= 1 && arity <= 6;
}
constexpr std::uint8_t boolean_table_bits(std::uint8_t arity) {
    return valid_boolean_arity(arity) ? static_cast<std::uint8_t>(1u << arity) : 0;
}
constexpr std::uint64_t boolean_function_count(std::uint8_t arity) {
    return (arity >= 1 && arity <= 5) ? (std::uint64_t{1} << boolean_table_bits(arity)) : 0;
}
constexpr bool eval_boolean(std::uint64_t truth, std::uint8_t arity,
                            std::uint8_t input_index) {
    if (!valid_boolean_arity(arity) || input_index >= boolean_table_bits(arity))
        return false;
    return ((truth >> input_index) & 1u) != 0;
}
constexpr std::uint8_t boolean_input_index(const bool* inputs, std::uint8_t arity) {
    if (!inputs || !valid_boolean_arity(arity)) return 0xff;
    std::uint8_t index = 0;
    for (std::uint8_t i = 0; i < arity; ++i)
        index = static_cast<std::uint8_t>((index << 1u) | (inputs[i] ? 1u : 0u));
    return index;
}
constexpr bool eval_boolean_inputs(std::uint64_t truth, std::uint8_t arity,
                                   const bool* inputs) {
    return eval_boolean(truth, arity, boolean_input_index(inputs, arity));
}

struct ScratchDescriptor {
    std::uint32_t arena = 0;
    std::uint64_t offset = 0;
    std::uint64_t bytes = 0;
    std::uint32_t alignment = 1;
    std::uint64_t generation = 0;
    std::uint64_t lease = 0;
    std::uint8_t owner_runner = 0xff; // 0..5, or 0xff for shared/control
    bool writable = false;
    constexpr bool valid(std::uint64_t arena_bytes) const {
        if (!bytes || !alignment || (alignment & (alignment - 1u)) != 0) return false;
        if (offset % alignment != 0 || offset > arena_bytes) return false;
        if (bytes > arena_bytes - offset) return false;
        return owner_runner == 0xff || owner_runner < 6;
    }
};

// Bounded runner scratch, deliberately separate from the 8 MiB palindrome
// chart. It is an in-process scratch arena only; persistence/RAM spill are
// separate adapters and cannot be inferred from this class.
class ScratchArena {
public:
    explicit ScratchArena(std::uint32_t arena_id, std::size_t capacity)
        : arena_id_(arena_id), storage_(capacity, 0) {}

    std::optional<ScratchDescriptor> allocate(
        std::uint64_t bytes, std::uint32_t alignment,
        std::uint64_t generation, std::uint64_t lease,
        std::uint8_t owner_runner, bool writable = true) {
        std::lock_guard<std::mutex> guard(mutex_);
        ScratchDescriptor probe{arena_id_, 0, bytes, alignment, generation,
                                 lease, owner_runner, writable};
        if (!bytes || !alignment || (alignment & (alignment - 1u)) != 0 ||
            (owner_runner != 0xff && owner_runner >= 6) ||
            bytes > storage_.size()) return std::nullopt;
        std::vector<ScratchDescriptor> ordered = allocations_;
        std::sort(ordered.begin(), ordered.end(),
                  [](const auto& a, const auto& b) { return a.offset < b.offset; });
        std::uint64_t candidate = 0;
        for (const auto& used : ordered) {
            candidate = (candidate + alignment - 1u) &
                        ~static_cast<std::uint64_t>(alignment - 1u);
            if (candidate <= used.offset && bytes <= used.offset - candidate) break;
            if (candidate < used.offset + used.bytes)
                candidate = used.offset + used.bytes;
        }
        candidate = (candidate + alignment - 1u) &
                    ~static_cast<std::uint64_t>(alignment - 1u);
        probe.offset = candidate;
        if (!probe.valid(storage_.size())) return std::nullopt;
        allocations_.push_back(probe);
        return probe;
    }

    bool write(const ScratchDescriptor& ref, std::uint64_t offset,
               const std::uint8_t* data, std::size_t bytes) {
        std::lock_guard<std::mutex> guard(mutex_);
        if (!matches(ref) || !ref.writable || (!data && bytes) ||
            offset > ref.bytes || bytes > ref.bytes - offset) return false;
        if (bytes == 0) return true;
        std::copy(data, data + bytes,
                  storage_.begin() + static_cast<std::ptrdiff_t>(ref.offset + offset));
        return true;
    }

    bool read(const ScratchDescriptor& ref, std::uint64_t offset,
              std::uint8_t* out, std::size_t bytes) const {
        std::lock_guard<std::mutex> guard(mutex_);
        if (!matches(ref) || (!out && bytes) ||
            offset > ref.bytes || bytes > ref.bytes - offset) return false;
        if (bytes == 0) return true;
        std::copy(storage_.begin() + static_cast<std::ptrdiff_t>(ref.offset + offset),
                  storage_.begin() + static_cast<std::ptrdiff_t>(ref.offset + offset + bytes),
                  out);
        return true;
    }

    bool release(const ScratchDescriptor& ref) {
        std::lock_guard<std::mutex> guard(mutex_);
        for (auto it = allocations_.begin(); it != allocations_.end(); ++it) {
            if (same_lease(*it, ref)) {
                std::fill(storage_.begin() + static_cast<std::ptrdiff_t>(ref.offset),
                          storage_.begin() + static_cast<std::ptrdiff_t>(ref.offset + ref.bytes), 0);
                allocations_.erase(it);
                return true;
            }
        }
        return false;
    }

    std::size_t capacity() const { return storage_.size(); }
    std::size_t active_allocations() const {
        std::lock_guard<std::mutex> guard(mutex_);
        return allocations_.size();
    }

private:
    static bool same_lease(const ScratchDescriptor& a, const ScratchDescriptor& b) {
        return a.arena == b.arena && a.offset == b.offset && a.bytes == b.bytes &&
               a.alignment == b.alignment && a.generation == b.generation &&
               a.lease == b.lease && a.owner_runner == b.owner_runner &&
               a.writable == b.writable;
    }
    bool matches(const ScratchDescriptor& ref) const {
        if (ref.arena != arena_id_ || !ref.valid(storage_.size())) return false;
        return std::any_of(allocations_.begin(), allocations_.end(),
                           [&](const auto& item) { return same_lease(item, ref); });
    }

    std::uint32_t arena_id_;
    std::vector<std::uint8_t> storage_;
    std::vector<ScratchDescriptor> allocations_;
    mutable std::mutex mutex_;
};

} // namespace nanlm
