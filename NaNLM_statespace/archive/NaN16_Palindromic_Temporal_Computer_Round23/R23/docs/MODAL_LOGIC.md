# Modal logic on NaN16 (Round 23)

## Semantics

Kripke model \(M = (W, R, V)\):

- \(W\) — worlds (≤ 8)
- \(R \subseteq W × W\) — accessibility
- \(V(w,p)\) — propositional valuation

\[
\begin{align*}
M,w \models p &\iff V(w,p)\\
M,w \models \Box p &\iff \forall v\,(R(w,v) \Rightarrow M,v \models p)\\
M,w \models \Diamond p &\iff \exists v\,(R(w,v) \land M,v \models p)
\end{align*}
\]

## Frame conditions → axioms

| Frame property | Axiom | Schema |
|----------------|-------|--------|
| (all frames) | **K** | □(P→Q) → (□P → □Q) |
| Reflexive | **T** | □P → P |
| Transitive | **4** | □P → □□P |
| Symmetric | **B** | P → □◇P |
| Euclidean | **5** | ◇P → □◇P |

Duality (always): \(\Diamond P \leftrightarrow \neg\Box\neg P\).

## Epistemic

Agent accessibility \(R_a\); \(K_a P\) at \(w\) iff \(P\) holds in all \(R_a\)-successors of \(w\).

## Limits

Propositional modal fragment only; no full nested formula AST yet; □(P→Q) is a specialized evaluator.
