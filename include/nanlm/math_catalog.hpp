// Typed, versioned mathematical operation catalog primitives.
// This is a registry contract and executable Boolean core, not a claim that
// every listed mathematical family has an implementation yet.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>

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

} // namespace nanlm
