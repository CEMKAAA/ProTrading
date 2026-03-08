# 2026-03-02 Workbench Agent Memory - Phase 5

## Scope

Phase 5 improves retrieval quality with a hybrid lexical + semantic-lite matcher, while staying dependency-free (no external embedding service required).

## Implemented

1. Hybrid overlap scoring in memory search
   - `lexical`: exact token overlap (existing behavior, still used).
   - `semantic-lite`: overlap on expanded token sets using domain synonym mapping.
   - `chargram`: character 3-gram Jaccard similarity for typo/morphology resilience.

2. Trading-domain synonym expansion
   - Examples:
     - `fvg` <-> `fair value gap` / `imbalance`
     - `htf` <-> `higher timeframe`
     - `buy` <-> `long`, `sell` <-> `short`
     - `mitigation` <-> `fill`/`touch`

3. Search acceptance logic update
   - A memory candidate is retained if it matches lexical or semantic overlap,
     or chargram similarity clears a small floor.

4. Backward compatibility
   - No schema changes.
   - Existing policy controls and scoring dimensions (importance, recency, scope, pin bonus) remain active.

## Outcome

Memory retrieval is more robust to:

1. Trading shorthand and abbreviations (FVG/HTF/LTF).
2. Wording variation ("long" vs "buy", "fair value gap" vs "fvg").
3. Small textual variations/typos.

