# Knowledge Graph Modeling Case: Approach and First Solution

**Author:** Bilge Cetin
**Date:** 2026-09-21

> Note: This is not a complete solution — it's an approach and a first iteration. Since I knew the problem was hard and open-ended, I built the core first and then wrote down the boundaries and open questions. I used AI assistance while working: I learned the concepts (property graph, RDF, recursive CTE) from it and adapted the examples to my own scenario.

\---

## 1\. How I understood the problem

* We have pieces of information (documents). The real value isn't in the pieces themselves, but in **the relationships between them**.
* Relationships have types (`source`, `progress-next`, ...). These types will evolve over time: new ones will be added, some will be renamed.
* There are two separate design questions, and I deliberately **kept them apart**:

  1. **Notation:** for humans — simple, easy to read and write.
  2. **Data model:** for software — can be as detailed and complex as needed.
* Core design idea: **the notation is a "view", the data model is the "source of truth."** A parser/compiler sits between them. Humans only write the notation; tables and other representations are derived from it.

## 2\. Assumptions

1. Documents must be movable/renameable, so a permanent identity independent of the title is needed.
2. Some relationships will carry their own metadata (who added it, when, confidence score). AI-generated content creates this need.
3. Relationship types must be stored as **data**, not hard-coded.
4. At the start there's a small team and a couple dozen relationship types, so a low-maintenance solution should be preferred.
5. Notation files are treated as the single source of truth.

## 3\. The example scenario I chose

I imagined a team running a "Mobile v2 launch" project. Slack messages, meeting notes, decisions, tasks, and AI-generated summaries are all linked to each other. This scenario naturally includes these relationship types: source, next step, supersession, part-whole, and contradiction.

Example questions the graph should be able to answer:

* Which decision is currently in effect?
* What sources does an AI summary rely on?
* If a message turns out to be wrong, what does it affect?
* What comes after a given task?
* Which AI summary has been disputed?

\---

## 4\. Question 1: Notation

**Inspiration:** Logseq's `id::` and `key:: value` syntax. From Turtle I only borrowed the "subject predicate object" logic and the idea of comma-separated multiple values.

### Rules

|Rule|Description|
|-|-|
|Block|A `- Title` line followed by indented lines beneath it|
|`id::`|Required, unique, immutable (in practice a ULID; shown as `d01` in the example for readability)|
|`type::`|Required|
|`key:: value`|If the key exists in the `rel_type` table it's a **relationship**, otherwise it's a **property**|
|Multiple values|Comma-separated: `source:: d04, d02`|
|Edge metadata|`{key: value}` after the target|
|Inverse relation|Never written, always auto-derived (`source-of`)|

To add a new relationship type, the notation itself doesn't change — you just add a row to the `rel_type` table.

### Example document

```
- Project: Mobile v2 launch
  id:: d00
  type:: project
  owner:: ayse

- Slack: "Payment SDK crashes on iOS"
  id:: d01
  type:: message
  author:: mehmet
  date:: 2026-09-14

- Weekly sync meeting
  id:: d02
  type:: meeting
  date:: 2026-09-15

- Blocker: Payment crash on iOS
  id:: d03
  type:: blocker
  derived-from:: d01
  source:: d02

- Decision: Stay on Payment SDK v3
  id:: d08
  type:: decision
  date:: 2026-09-01

- Decision: Upgrade to SDK v4
  id:: d04
  type:: decision
  date:: 2026-09-15
  source:: d03, d02
  supersedes:: d08
  part-of:: d00

- Task: SDK v4 integration
  id:: d05
  type:: task
  status:: done
  owner:: mehmet
  part-of:: d00
  implements:: d04
  resolves:: d03
  progress-next:: d06

- Task: iOS regression testing
  id:: d06
  type:: task
  status:: in-progress
  owner:: ayse
  part-of:: d00
  progress-next:: d07

- Task: Submit to the App Store
  id:: d07
  type:: task
  status:: todo
  part-of:: d00

- MrBrief: Weekly status summary
  id:: d09
  type:: ai-summary
  date:: 2026-09-17
  generated-by:: ai-assistant
  source:: d04 {confidence: 0.9}, d05 {confidence: 0.8}

- Slack: "SDK v4 causes slowness on Android"
  id:: d10
  type:: message
  author:: ayse
  date:: 2026-09-18
  contradicts:: d09 {by: ayse, date: 2026-09-18}
```

Two deliberate choices I made:

* I didn't add a "resolved?" field to `d03`. It can be derived from the `d05 resolves:: d03` relationship.
* `d03` was written with the old name `derived-from` instead of `source`. The point is to show that when a relationship name evolves, existing data doesn't break.

\---

## 5\. Question 2: Data model

**Choice:** Property graph model. Starting storage: PostgreSQL. Rationale in section 8.

### Schema

```sql
CREATE TABLE rel_type (
  name          text PRIMARY KEY,
  inverse       text,                              -- name of the inverse direction
  symmetric     boolean NOT NULL DEFAULT false,
  transitive    boolean NOT NULL DEFAULT false,
  deprecated_by text REFERENCES rel_type(name),    -- old name -> new name
  from_types    text[],                            -- valid source types (NULL = any)
  to_types      text[],                            -- valid target types
  description   text
);

CREATE TABLE node (
  id         text PRIMARY KEY,                     -- ULID
  type       text NOT NULL,
  title      text NOT NULL,
  body       text,
  props      jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE edge (
  id         bigserial PRIMARY KEY,
  from_id    text NOT NULL REFERENCES node(id),
  rel_type   text NOT NULL REFERENCES rel\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\_type(name),
  to_id      text NOT NULL REFERENCES node(id),
  props      jsonb NOT NULL DEFAULT '{}',          -- confidence, by, date ...
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (from_id, rel_type, to_id)
);

CREATE INDEX ON edge (from_id, rel_type);
CREATE INDEX ON edge (to_id, rel_type);

-- View that maps old relationship names to new ones; queries use this
CREATE VIEW edge_v AS
SELECT e.id, e.from_id, COALESCE(r.deprecated_by, r.name) AS rel, e.to_id, e.props
FROM edge e JOIN rel_type r ON r.name = e.rel_type;
```

### `rel_type` contents

|name|inverse|symmetric|transitive|deprecated\_by|valid endpoints|
|-|-|-|-|-|-|
|source|source-of|no|yes||any → any|
|derived-from||no|yes|**source**|(old name)|
|supersedes|superseded-by|no|yes||any → any|
|part-of|has-part|no|no||any → project|
|progress-next|progress-prev|no|no||task → task|
|implements|implemented-by|no|no||task → decision|
|resolves|resolved-by|no|no||task → blocker|
|contradicts|(itself)|**yes**|no||any → any|

### `node` contents

|id|type|title|props|
|-|-|-|-|
|d00|project|Mobile v2 launch|owner=ayse|
|d01|message|Slack: crashes on iOS|author=mehmet, date=09-14|
|d02|meeting|Weekly sync|date=09-15|
|d03|blocker|Payment crash on iOS||
|d04|decision|Upgrade to SDK v4|date=09-15|
|d05|task|SDK v4 integration|status=done, owner=mehmet|
|d06|task|iOS regression testing|status=in-progress, owner=ayse|
|d07|task|Submit to the App Store|status=todo|
|d08|decision|Stay on SDK v3|date=09-01|
|d09|ai-summary|Weekly status summary|date=09-17|
|d10|message|Slack: slowness on Android|author=ayse, date=09-18|

### `edge` contents (each relationship in the notation becomes one row)

|from|rel_type|to|props|
|-|-|-|-|
|d03|derived-from|d01||
|d03|source|d02||
|d04|source|d03||
|d04|source|d02||
|d04|supersedes|d08||
|d04, d05, d06, d07|part-of|d00|(4 rows)|
|d05|implements|d04||
|d05|resolves|d03||
|d05|progress-next|d06||
|d06|progress-next|d07||
|d09|source|d04|confidence=0.9|
|d09|source|d05|confidence=0.8|
|d10|contradicts|d09|by=ayse, date=2026-09-18|

\---

## 6\. Proof that the model answers the questions

**Q1. Which decision is currently in effect?**

```sql
SELECT id, title FROM node n
WHERE type = 'decision'
  AND NOT EXISTS (SELECT 1 FROM edge_v WHERE rel = 'supersedes' AND to_id = n.id);
```

Result: **d04**. It's excluded from being superseded because `d08` is pointed to by a `supersedes` edge.

**Q2. What sources does the AI summary (d09) rely on?**

```sql
WITH RECURSIVE origins AS (
  SELECT to_id AS id FROM edge_v WHERE from_id = 'd09' AND rel = 'source'
  UNION
  SELECT e.to_id FROM edge_v e JOIN origins o ON e.from_id = o.id
  WHERE e.rel = 'source'
)
SELECT n.id, n.title FROM origins o JOIN node n ON n.id = o.id;
```

Result: **d04, d05, d03, d02, d01**. The `d03 → d01` link is stored under the old name `derived-from`, but since the view exposes it as `source`, it's still caught.

**Q3. What is affected if d01 turns out to be wrong? (impact analysis)**

```sql
WITH RECURSIVE affected AS (
  SELECT from_id AS id FROM edge_v WHERE to_id = 'd01' AND rel = 'source'
  UNION
  SELECT e.from_id FROM edge_v e JOIN affected a ON e.to_id = a.id
  WHERE e.rel = 'source'
)
SELECT n.id, n.type, n.title FROM affected a JOIN node n ON n.id = a.id;
```

Result: **d03, d04, d09**. If the message is wrong, the AI summary needs to be refreshed too.

**Q4. What tasks come after d05?**

```sql
WITH RECURSIVE sequence AS (
  SELECT to_id AS id, 1 AS step FROM edge_v
  WHERE from_id = 'd05' AND rel = 'progress-next'
  UNION ALL
  SELECT e.to_id, s.step + 1 FROM edge_v e JOIN sequence s ON e.from_id = s.id
  WHERE e.rel = 'progress-next' AND s.step < 50   -- cycle safety
)
SELECT s.step, n.title, n.props->>'status' AS status
FROM sequence s JOIN node n ON n.id = s.id ORDER BY s.step;
```

Result: 1. iOS regression testing (in-progress), 2. Submit to the App Store (todo).

**Q5. Which AI summary has been disputed, and by whom?**

```sql
SELECT s.id AS summary, o.id AS dispute, o.title, c.props
FROM node s
JOIN edge_v c ON c.rel = 'contradicts' AND s.id IN (c.from_id, c.to_id)
JOIN node o ON o.id = CASE WHEN c.from_id = s.id THEN c.to_id ELSE c.from_id END
WHERE s.type = 'ai-summary';
```

Result: `d09 ← d10`, `{"by": "ayse", "date": "2026-09-18"}`. Because `contradicts` is symmetric, both directions are checked.

\---

## 7\. Notation, data model, and RDF/Turtle equivalent

|Notation|Data model|Turtle (if needed)|
|-|-|-|
|`id:: d04`|`node.id`|`d:d04`|
|`type:: decision`|`node.type`|`a k:Decision`|
|`date:: 2026-09-15`|`node.props`|`k:date "2026-09-15"`|
|`source:: d03, d02`|2 `edge` rows|`k:source d:d03, d:d02`|
|`{confidence: 0.9}`|`edge.props`|RDF-star: `<< d:d09 k:source d:d04 >> k:confidence 0.9`|

The RDF equivalent of the schema side is roughly:

```turtle
k:source       a owl:ObjectProperty ; owl:inverseOf k:sourceOf .
k:derivedFrom  rdfs:subPropertyOf k:source .
k:contradicts  a owl:SymmetricProperty .
```

Turtle can be generated with an exporter if it's ever needed.

\---

## 8\. Design decisions and alternatives

**Why property graph (instead of RDF)?**

* We need edges to carry their own properties (confidence score, who/when). This is natural in a property graph; RDF requires RDF-star for it.
* Easier for the team to learn and debug.
* RDF's strengths (merging with external data, automated reasoning, SHACL) aren't a need right now. A Turtle export can be added if the need arises.

**Why PostgreSQL to start?**

* Simple to set up and operate for a small team; keeps all the data in one place.
* Graph traversal can be done with recursive CTEs.
* Because the model is a property graph, migrating to Neo4j is a direct path later (the node/edge tables are already the same shape). This can be reconsidered if queries get too complex or traversals get too deep.

**Other decisions**

1. **Derivable information is not stored:** inverse relationships, "which decision is old," and "is the blocker resolved" are all inferred from edges. This prevents inconsistency.
2. **Relationship types are data:** the `rel_type` table holds the inverse direction, symmetry, transitivity, old name, and valid endpoints. Renaming doesn't break old records, thanks to `deprecated_by`.
3. **Edges are first-class entities:** metadata can be attached to a relationship.
4. **Stable identity:** the ID stays fixed even if the title or location changes.

### Validation rules (on the software side)

* A key not present in `rel_type` is treated as a property.
* A relationship's endpoints must match `from_types` / `to_types` (e.g., `resolves` only goes task → blocker).
* The target `id` must exist (no dangling links).
* No cycles allowed in `progress-next` and `supersedes` chains.
* A relationship written in the reverse direction triggers a warning.

(This is a hand-rolled version of a SHACL-like approach; it could be moved to SHACL if RDF is adopted.)

\---

## 9\. What I didn't solve in this version, and open questions

I left these out deliberately; they should be addressed in the next iterations.

1. **Notation grammar ambiguity:** the comma inside `{by: ayse, date: ...}` can be confused with the comma used for multiple values. The parser should treat the curly braces as a group, or a separate edge-metadata syntax should be considered.
2. **Ordering:** if the `progress-next` chain is meant to represent a list, how should branching (two next steps from one task) and out-of-order sequences be handled? A separate "ordered list" structure may be needed.
3. **Versioning:** when a document's content changes, what happens to references made to the old version? Is `supersedes` enough, or is a separate version table needed?
4. **Mapping notation to data:** is a single file multiple nodes, or one node per file? How will merge conflicts be resolved in a tool like Git?
5. **`rel_type` governance:** who adds a new relationship type, who approves it? How does the migration process for a name change work?
6. **Meaning of `transitive`:** does the field only store information, or does the query engine act on it? In this first version I wrote the recursive queries by hand.
7. **Access control and multiple teams:** is different teams' data separate or shared? Is edge-level access control needed?
8. **Traceability of AI output:** which model produced what, and when, from what input? For now there's `generated-by` and `confidence`; whether that's enough is unclear.
9. **Scale and performance:** is Postgres sufficient for deep chains and large data volumes? Not measured yet.
10. **Surfacing inverse relationships when reading:** when a user opens `d04`, a view showing "things that point to me as a source" is needed; not designed yet.

## 10\. My next steps

1. Write a formal grammar (EBNF) for the notation.
2. Write a small parser (Python) that compiles the notation into `node`/`edge` tables, and implement the validation rules.
3. Try it out on a real set of documents and see which relationship types are missing.
4. Test simplicity with the team (especially the people who will write the notation): is it actually easy?
5. Write the Turtle exporter and confirm the model's RDF-convertibility.

## 11\. Process note

* I first learned the concepts (node/edge, property graph, RDF, recursive CTE), then tackled the two questions separately.
* I started with a small example and progressively added challenges to it — edge metadata, old names, inverse relationships.
* For every design decision I tried to note an alternative and a rationale. In a few places (ordering, versioning) I admitted I didn't know the right answer and left them as open questions.

