# Graph-Spectral Foundation for the 8 MiB Universe

Status: architecture specification and implementation contract. Mathematical results, implementable operators, and experimental hypotheses are explicitly separated. This document does not claim that a physical membrane, quantum tunneling, cognition-as-wave, or noospheric transmission has been demonstrated.

## 1. Decision and dependency direction

Adopt a reusable **Relational-Spectral Subsystem (RSS)** as a foundational operator layer for every 8 MiB universe-bin. RSS operates over the existing 256-Head topology and its 256×256 directed relationship matrix. It does not replace NaN16 addressing, pair-cell storage, the global ledger, hypergraph, or MTH.

Dependency direction:

NaN16 topology/storage → MTH native arithmetic and vector kernels → RSS graph operators → NaNNet transport/runner scheduling → NaNLMind relation learning and use.

The 8 MiB bin is a storage/coordination envelope, not a claim that all 65,536 coefficients are simultaneously materialized as floating-point values. RSS must support sparse, fixed-point, tiled, and bounded-workspace execution.

## 2. Exact topology contract

For one chart/universe:
- Vertices/Heads: V={0,…,255}, |V|=256.
- Unordered pair cells: C(256,2)=32,640.
- Directed non-self relationships: 256·255=65,280.
- Diagonal/self states: 256.
- Directed matrix slots including diagonal: 256²=65,536.

Addressing remains addr(a,b)=(a << 8) | reverse8(b), and 16-bit reversal transposes the matrix: R(addr(a,b))=addr(b,a).

The pair cell stores two independent directed values. Do not collapse them. The 256 diagonal fixed points are vertex/self states, not 256 additional edges in the simple-graph convention.

The existing 8 MiB universe-bin layout remains authoritative. RSS state must occupy an explicitly versioned region/sidecar in that envelope or referenced bounded pages. Before assigning bytes, update actual layout constants and prove the complete allocation; do not silently consume head scratch, address registers, ledger, or hypergraph storage.

## 3. Three distinct mathematical objects

### 3.1 Directed relation matrix W

W is a 256×256 matrix of directed relation strengths (or a fixed-point/integer encoded analogue). In general W != Wᵀ. Diagonal entries have separately defined self-state semantics and are excluded from ordinary graph degree unless a particular operator says otherwise.

Decompose:
- W_s=(W+Wᵀ)/2
- W_a=(W-Wᵀ)/2

Then W_sᵀ=W_s, W_aᵀ=-W_a, and W=W_s+W_a. This preserves reciprocal and directional information. It is an operator view, not a rewrite of stored pair rails.

### 3.2 Symmetric coupling A and graph Laplacian L

For stable undirected diffusion/wave dynamics, derive A with A=Aᵀ, A_ij≥0, and A_ii=0 unless a separately specified self-loop convention is used. The derivation policy from W must be explicit. A safe baseline is A_ij=max(0,W_s,ij) after documented scaling/normalization. Absolute symmetric strength, confidence weighting, and learned couplings are separately named policies. Never silently symmetrize canonical W.

Define D_ii=Σ_j A_ij and L=D-A. For any real x:

xᵀLx = (1/2) Σ_ij A_ij(x_i-x_j)² ≥ 0.

Thus L is symmetric positive semidefinite. Its nullity equals the number of connected components for positive-weight connectivity.

For unweighted K256, A=J-I, D=255I, L=256I-J. Its spectrum is 0 (multiplicity 1) and 256 (multiplicity 255). This is a baseline oracle, not the assumed spectrum of a learned/nonuniform topology.

### 3.3 Pair-space / product-graph operator

A 256×256 matrix can be vectorized as a 65,536-component state u=vec(U). If U is a field over ordered pairs (a,b), the two-coordinate graph Laplacian is:

L_pair = L ⊗ I + I ⊗ L.

A separable basis is φ_m(a)φ_n(b), and U_ab(t)=Σ_mn q_mn(t)φ_m(a)φ_n(b).

For K256, product eigenvalues are λ_m+λ_n: 0 once, 256 with multiplicity 510, and 512 with multiplicity 65,025. These are pair-space modes, not 65,536 independently fitted eigenvalues of a 256×256 matrix. A 256×256 symmetric matrix itself has 256 eigenvalues/eigenvectors.

Use the 256-dimensional graph operator for Head-state dynamics. Use the 65,536-dimensional product operator only when the state genuinely lives on ordered Head pairs. Implement product action matrix-free as LU+ULᵀ (for symmetric L, LU+UL), never materializing a 65,536² matrix.

## 4. Graph-wave equation and sign convention

With L=D-A≥0, define:

ü + c²Lu = 0

and with diagonal potential and source:

ü + [c²L+V]u = f(t).

This sign convention keeps L positive semidefinite and a nonnegative V adds nonnegative stiffness. If Δ=-L, the equivalent form is ü-c²Δu+Vu=f. Never mix conventions.

For symmetric H=c²L+V, eigenmodes satisfy Hφ_k=μ_kφ_k and ω_k=√μ_k. Negative μ indicates an unstable mode or invalid parameterization; never hide it by taking an absolute value. An undriven stable solution is u(t)=Σ_k[a_k cos(ω_kt)+b_k sin(ω_kt)]φ_k.

For deterministic discrete execution, prefer a symplectic/leapfrog integrator with fixed-point arithmetic. For u_(t+1)=2u_t-u_(t-1)-h²Hu_t+h²f_t, a sufficient linear stability condition is h²μ_max≤4. Validate saturation and rounding separately. Every fixed-point kernel documents Q format, intermediate width, rounding, overflow status, and replay determinism.

## 5. Void potential: implementable operator, not a discovered physical hole

The inverse-square family is a useful optional potential:

V_i = α/(r_i+ε)².

Here r_i is a defined computational radial coordinate, ε>0 regularizes the singularity, and α is configured. Units are computational unless a full physical model and unit mapping are supplied. A graph has no inherent Euclidean radius. Select and version one of:

1. Graph-distance radius: choose anchor Heads and calculate shortest-path distance under a declared edge-length transform. Disconnected vertices require explicit infinity/sentinel behavior.
2. Embedding radius: deterministic coordinates for Heads with embedding version and metric.
3. Topology-shell radius: BFS hop count from a center set. Cheap and robust, but not Euclidean geometry.

Do not infer radius from Head numeric index or the 16×16 display arrangement unless that arrangement is formally selected as geometry.

For α>0, V raises local restoring force and can suppress low-frequency amplitude near large V under suitable forcing/boundary conditions. It does not prove that high-angular-momentum modes are attracted to a boundary, that a maximum-amplitude ring forms, or that exactly 256 antinodes occur. Those are measurements, not consequences of the definition.

The quantum centrifugal coefficient ℏ²l(l+1)/(2μr²) belongs to a continuum radial Schrödinger problem with defined dimension, mass, angular momentum, and units. RSS α is a computational parameter unless a physical mapping is established. Do not label RSS propagation as quantum mechanics.

Void experiments:
- central suppression: compare center-shell energy with V disabled/enabled;
- boundary concentration: measure shell energy and eigenvector participation ratio;
- barrier transmission: compare transfer across a low-coupling annulus with/without V;
- sweep α, ε, center set, coupling graph, source location/frequency;
- controls: α=0, uniform complete graph, seeded random graph, disconnected graph.

“Tunneling-like” means measurable nonzero transfer across a computationally suppressed region; it is not quantum tunneling. “Creative insight” is not a physical consequence of this equation and must not be claimed from a transition alone.

## 6. Standing-wave interpretation

A modal expansion over pair-space is well-defined:

U_ab(t)=Σ_mn q_mn(t)φ_m(a)φ_n(b).

The proposed double-index expression with amplitudes, basis functions, frequencies, and phases is valid only after specifying the graph/coordinate basis, the operator defining its eigenmodes, pair-space frequencies, boundary/anchor conditions, coefficient/phase representation, and whether U is real, complex, or fixed-point encoded.

For L_pair=L⊗I+I⊗L, ω_mn=c√(λ_m+λ_n). A general coupled pair-space operator need not be separable.

A “ring of power” is a measured shell concentration, not a theorem. 256 vertices do not guarantee 256 antinodes. Antinodes depend on eigenvectors, forcing, potential, and graph geometry.

## 7. Eigensystems and numerical methods

For real symmetric H, use H=PΛPᵀ with orthonormal columns. For complex Hermitian H, use H=PΛP†. Complexification alone does not make a matrix Hermitian; require H=H†.

For arbitrary directed W, a real orthogonal eigendecomposition may not exist. Keep W directed; analyze W_s and W_a separately or use a justified non-symmetric method (Schur decomposition, singular values, or left/right eigenvectors).

Implementation tiers:
- Tier 0 exact oracles: K256 spectrum, small hand-built graphs, symmetry and energy identities.
- Tier 1 matrix-free operators: sparse A, degree accumulation, Lx, pair-space action, Vx.
- Tier 2 iterative spectral analysis: deterministic Lanczos for symmetric operators; fixed iteration count, reorthogonalization policy, residual, convergence status, eigenvalue ordering/tie policy.
- Tier 3 full eigendecomposition only when measured memory/latency justifies it. 256×256 is modest; 65,536×65,536 dense storage is forbidden.
- Tier 4 online approximations: Chebyshev filters, low-rank subspaces, block Krylov, cached top-k modes. Version approximation degree and error bounds.

Every eigenpair returns residual ||Hφ-μφ||, normalization status, iteration count, operator digest/version, and numeric format. Poor residual means invalid eigenpair.

## 8. Directedness, transpose, palindrome and centrosymmetry

Address reversal proves matrix transposition: R(addr(a,b))=addr(b,a). It does not prove centrosymmetry.

Centrosymmetry requires JWJ=W, equivalently W_ij=W_(255-i,255-j), where J reverses Head order. This is independent of transpose symmetry W=Wᵀ. A matrix may satisfy either, both, or neither.

For verified centrosymmetric symmetric matrices, reversal-even and reversal-odd subspaces can reduce the eigensystem to two 128×128 blocks. This is legal only after checking JWJ=W and W=Wᵀ (or appropriate commuting/Hermitian conditions). The current palindrome mirror pairing alone is insufficient. FOLD must verify invariance or use a validated certificate; otherwise fall back.

For pair-space U, U=Uᵀ is another independent optional invariant. Directed information must remain available when U is not symmetric.

## 9. Six stable RSS operations

1. ENCODE: write directed updates to existing rails; preserve direction, provenance, confidence, epoch, source.
2. QUERY: apply L/H or project onto a validated cached basis; return operator version and residual.
3. MATCH: compare query coefficients with stored spectral signatures; normalize scale and expose metric/threshold. Spectral similarity is not semantic identity.
4. FILTER: apply g(H) using validated basis or polynomial approximation. Read-only unless explicitly committed.
5. DRIVE: inject bounded f(t), with source identity, duration, energy budget, and reversible/ledgered commit semantics.
6. FOLD: exploit verified transpose, centrosymmetry, block, sparsity, or low-rank structure. Never infer symmetry from naming or visual layout.

Additional primitives: degree, connected components, Laplacian apply, potential apply, pair-space apply, energy, shell histogram, spectral signature, eigenpair residual, sparse edge update, operator digest.

## 10. Pattern analysis and language-model use

RSS is a reusable pattern-analysis substrate, not a separate mind or identity. NaNLMind should be able to map neighborhoods and directed motifs to Head/edge cells; compare subgraphs by degree profile, labels, signed/directed motifs, and spectral signatures; detect communities/components and epoch changes; find recurring normalized spectral patterns; query multi-hop propagation and pair-space correlations; filter noisy relation fields without overwriting source relations; drive candidate activations with recorded transitions; compare pre/post spectra for learning diagnostics; and expose uncertainty, provenance, operator digest, and approximation error.

A spectral signature is lossy. It cannot replace exact relation records, source text, provenance, or semantic validation. Matches are candidates for downstream validation, not truth labels. The global ledger and hypergraph remain canonical semantic state.

A dedicated MC0 pattern-analysis program is a later consumer. RSS exposes a stable, versioned API so MC0 can be added without changing storage or duplicating kernels.

## 11. NaN16/MTH implementation boundary

All mathematical kernels belong in native NaN16 .nas modules under MTH. Host-language code may handle orchestration, file I/O, RPC, memory mapping, scheduling, and test harnesses, but must not substitute host floating-point/linear-algebra routines for native kernels.

MTH stages:
A. fixed-point vector ABI and checked arithmetic;
B. sparse edge traversal and deterministic degree accumulation;
C. symmetric coupling derivation/validation;
D. Laplacian-vector product;
E. potential-vector product and safe inverse-square lookup/division;
F. pair-space operator without materializing Kronecker matrix;
G. energy and shell statistics;
H. polynomial spectral filter;
I. deterministic Lanczos/iterative eigensolver;
J. optional 256×256 dense symmetric eigensolver after measured need;
K. validated symmetry/FOLD routines;
L. wave time-stepper and bounded source injection.

Every kernel defines NaN16 ABI, register clobbers, caller-owned scratch frame, overlap rules, Q format, overflow status, deterministic behavior. No shared static return slots. Use sparse/tiled workspaces and preflight writes where failure must be atomic.

Canonical MTH assembler/interpreter is the acceptance gate. Source-written fixtures are not passing tests until assembled and executed.

## 12. NaNNet runners and universe integration

Runners are execution/transport agents, not alternate numerical authorities. A versioned RSS job descriptor contains universe/chart ID and topology digest; operator type/version and sparse/dense layout; input/output page refs and lengths; Q format and overflow policy; source/anchor/void configuration; deterministic seed only when needed; iteration/step budget and cancellation epoch; expected output digest and result metadata contract.

Runners advertise capability bits: sparse graph apply, pair-space apply, fixed-point vector kernels, polynomial filter, Lanczos, wave stepper, validated FOLD, maximum workspace. Scheduler dispatches only to verified compatible capabilities and memory budgets.

NANNET messages carry immutable/versioned page references rather than copying dense matrices. Results include completion status, operator/output digests, residual/error bounds, saturation count, iteration count, runtime, runner capability/version. Stale epoch or mismatched topology/operator digest is rejected. Semantic commits flow through existing NaNLMind validation and ledger; runners do not independently mutate global semantic truth.

## 13. 8 MiB allocation and scaling

Do not hard-code RSS as 65,536 float64 values. The matrix is a logical address space. Candidate representations: sparse edge values in existing pair cells; bit-packed adjacency/capability maps; Q-format weights where range permits; per-Head 256-vectors; tiled pair-space U; bounded iterative scratch; immutable cached low-rank/eigenbasis pages referenced by digest.

A full 256×256 Q16.16 matrix is 256 KiB; float64 is 512 KiB. A 65,536-component Q16.16 vector is 256 KiB. A dense 65,536² matrix is prohibitive and forbidden. Budget allocations against the 8 MiB bin and all existing structures with compile-time/startup proof.

The same RSS contract applies to each universe-bin. Cross-bin relationships remain global hyperedges/refs processed through NaNNet; no private per-runner semantic ledger.

## 14. Verification and acceptance gates

Exact mathematics:
- K256 spectrum (0×1, 256×255);
- L symmetry, zero row sums, nonnegative quadratic form;
- connected-component/nullity correspondence on small graphs;
- W_s/W_a decomposition;
- pair-graph action equals explicit small Kronecker oracle;
- K256 product spectrum;
- unforced/undamped wave energy conservation within declared fixed-point error;
- positive V does not introduce negative stiffness eigenvalues when L is PSD.

Void:
- radius policies on known graph fixtures;
- ε>0 and bounded V at r=0;
- α=0 reproduces baseline;
- measure center/shell energy and transfer; do not assert ring/tunneling in advance.

Spectral:
- eigenpair residual threshold by numeric format;
- orthogonality error;
- deterministic repeatability;
- Lanczos breakdown/restart behavior;
- degenerate eigenvalue ordering;
- no false FOLD when one edge breaks symmetry.

Systems:
- MTH native fixture execution;
- runner capability negotiation and stale-job rejection;
- NANNET page-ref transfer and output digest verification;
- NaNLMind read-only graph queries without bypassing semantic ledger;
- 8 MiB allocation budget proof;
- failure/cancellation/replay tests.

## 15. Implementation sequence

1. Freeze this specification and add RSS invariants to core math docs.
2. Audit universe-bin byte map; identify RSS region or sidecar-page contract.
3. Implement MTH vector and sparse graph primitives, native NaN16.
4. Add exact K256 and small-graph fixtures; run canonical NaN16 toolchain.
5. Add RSS operator descriptors and runner capability/result contracts.
6. Add NaNNet job routing and page-reference transfer; runners execute only advertised kernels.
7. Integrate NaNLMind read-only graph queries and spectral signatures.
8. Add pattern-analysis APIs: motifs, neighborhood fingerprints, shell statistics, spectral comparison.
9. Add void potential and wave stepper as opt-in operators.
10. Add Lanczos and polynomial filters; benchmark memory, deterministic error, latency.
11. Add validated FOLD only for matrices passing exact symmetry checks.
12. Later: MC0 dedicated pattern-analysis consumer.

## 16. Current evidence and non-claims

The repository already defines the 256-Head topology, 32,640 unordered pair cells, directed rails, NaN16 address transpose, a resonance subsystem, and an 8 MiB page constant. This proposal adds the graph-spectral mathematical contract.

At creation:
- graph-Laplacian/spectral architecture is specified;
- no RSS native NaN16 graph-wave or eigensolver kernel is claimed complete;
- no canonical MTH assembler execution is claimed;
- no NaNNet runner capability is claimed until implemented and exercised;
- no 256-node ring, 256 antinodes, quantum tunneling, creative-insight mechanism, or noospheric broadcast is established.

The next proof is small and exact: construct K256, derive L, apply L to known vectors, verify its two eigenvalues/multiplicities analytically and by a native fixture, then proceed to a sparse nonuniform graph.
