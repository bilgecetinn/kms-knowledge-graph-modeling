# Knowledge Graph Modeling Case

A small property-graph system for modeling the relationships *between* pieces of information (Slack messages, meeting notes, decisions, tasks, AI-generated summaries) rather than just the information itself — plus a human-friendly notation for writing that graph by hand, a PostgreSQL data model to store it, and a Turtle/RDF exporter for interop.

This repository is my solution to a take-home modeling case. The full write-up — problem framing, assumptions, design alternatives considered, and open questions — is in [`knowledge-graph-modeling-case.md`](./knowledge-graph-modeling-case.md).

## Why this exists

Most of what a team knows lives in scattered documents: a Slack message about a bug, a meeting where it was discussed, a decision that followed, tasks that implemented it, and an AI-generated summary that might later be contradicted by new information. Individually these documents aren't that valuable — what's valuable is knowing **how they connect**: what caused what, what superseded what, what a summary is actually based on.

The goal was to design two things, deliberately kept separate:

1. **A notation** — simple enough for a person to read and write by hand.
2. **A data model** — as detailed and rigorous as the software needs, since a parser (not a human) will maintain it.

The notation is the *view*; the data model is the *source of truth once loaded*. A parser translates one into the other.

## Concepts I worked with

* **Property graphs vs. RDF/Turtle** — trade-offs between a schema-flexible property graph (edges can carry their own metadata like `confidence` or `by` natively) versus RDF, where the same thing requires RDF-star (`<< s p o >> metadata`). I chose property graph for this stage and kept a Turtle export path open for later.
* **Schema-as-data** — relationship types (`source`, `part-of`, `progress-next`, ...) live in a `rel_type` table instead of being hard-coded, so the vocabulary can grow without code changes. This table also carries each relation's inverse name, whether it's symmetric or transitive, and a `deprecated_by` pointer so an old relation name (e.g. `derived-from`) keeps working after being renamed (to `source`) without rewriting historical data.
* **Recursive CTEs** — PostgreSQL's `WITH RECURSIVE` for graph traversal: tracing an AI summary back to its ultimate sources, doing impact analysis ("what breaks if this message is wrong"), and walking a `progress-next` task chain.
* **Stable identity vs. mutable presentation** — every node has a permanent ID (a ULID in practice, shown as `d01` etc. for readability) so titles, wording, or file location can change without breaking relationships.
* **Derived vs. stored information** — things like "which decision is currently active" or "is this blocker resolved" are *never stored directly*; they're computed from the edges (e.g., "not the target of any `supersedes` edge"), which rules out entire classes of data inconsistency.
* **Notation design trade-offs** — Logseq's `id::`/`key:: value` block syntax and Turtle's subject-predicate-object framing, adapted into a small grammar where a key is either a relationship (if it's a known relation name) or a plain property (otherwise), with `{key: value}` for edge-level metadata.
* **PostgreSQL as a graph store for a small team** — recursive CTEs, indexes on `(from_id, rel_type)` / `(to_id, rel_type)`, and a `edge_v` view that transparently maps deprecated relation names to their current name, so old data and new queries stay compatible.

## Repository contents

|File|What it is|
|-|-|
|`knowledge-graph-modeling-case.md`|The full design write-up: problem framing, assumptions, the example scenario, the notation spec, the data model, five example questions answered with real SQL, design alternatives considered, and open questions for future iterations.|
|`notation_txt.txt`|A sample notation file describing an 11-node scenario (a "Mobile v2 launch" project with a Slack bug report, a blocker, two competing decisions, three tasks, an AI-generated summary, and a contradicting follow-up message). This is the human-readable input.|
|`schema_and_data.sql`|The PostgreSQL schema (`rel_type`, `node`, `edge` tables plus the `edge_v` compatibility view) and the same sample dataset inserted by hand, as a reference/independent check against the parser's output.|
|`parse_notation.py`|Parses a notation file like `notation_txt.txt` into `node`/`edge` INSERT statements (`load_generated.sql`). This is what turns the human-writable notation into the database's source of truth.|
|`queries.sql`|Five example queries answering: which decision is currently active, what an AI summary's sources trace back to, what's affected if a message turns out to be wrong, what task comes next in a sequence, and which AI summary has been disputed.|
|`export_turtle.py`|Reads the PostgreSQL graph and exports it as RDF Turtle (`graph.ttl`), demonstrating that the property-graph model can be converted to RDF when/if that's needed.|
|`README.md`|This file.|

## How to run it

Requires PostgreSQL and Python 3 with `psycopg2-binary` and `rdflib`.

```bash
# 1. Create the schema and load the hand-written reference data
createdb kms_test
psql -d kms_test -v ON_ERROR_STOP=1 -f schema_and_data.sql

# 2. Run the example queries against it
psql -d kms_test -f queries.sql

# 3. Regenerate the same data from the human-writable notation instead,
#    to prove the notation -> parser -> database path works
python3 parse_notation.py notation_txt.txt --output load_generated.sql
psql -d kms_test -v ON_ERROR_STOP=1 -f load_generated.sql
psql -d kms_test -f queries.sql   # results should be identical to step 2

# 4. (Optional) export the graph as RDF Turtle
pip install psycopg2-binary rdflib --break-system-packages
python3 export_turtle.py --database kms_test --output graph.ttl
```

## Known limitations / next steps

See section 9 of [`knowledge-graph-modeling-case.md`](./knowledge-graph-modeling-case.md) for the full list — highlights: the notation's comma syntax can be ambiguous inside edge metadata, ordering/branching in `progress-next` chains isn't formally handled, and there's no versioning story yet for documents whose content changes after the fact.

