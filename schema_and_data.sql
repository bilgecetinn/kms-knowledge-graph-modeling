DROP VIEW IF EXISTS edge_v;
DROP TABLE IF EXISTS edge;
DROP TABLE IF EXISTS node;
DROP TABLE IF EXISTS rel_type;

CREATE TABLE rel_type (
  name text PRIMARY KEY,
  inverse text,
  "symmetric" boolean NOT NULL DEFAULT false,
  transitive boolean NOT NULL DEFAULT false,
  deprecated_by text REFERENCES rel_type(name),
  from_types text[],
  to_types text[],
  description text
);

CREATE TABLE node (
  id text PRIMARY KEY,
  type text NOT NULL,
  title text NOT NULL,
  body text,
  props jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE edge (
  id bigserial PRIMARY KEY,
  from_id text NOT NULL REFERENCES node(id),
  rel_type text NOT NULL REFERENCES rel_type(name),
  to_id text NOT NULL REFERENCES node(id),
  props jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (from_id, rel_type, to_id)
);

CREATE INDEX edge_from_rel_idx ON edge (from_id, rel_type);
CREATE INDEX edge_to_rel_idx ON edge (to_id, rel_type);

CREATE VIEW edge_v AS
SELECT
  e.id,
  e.from_id,
  COALESCE(r.deprecated_by, r.name) AS rel,
  e.to_id,
  e.props
FROM edge e
JOIN rel_type r ON r.name = e.rel_type;

INSERT INTO rel_type
(name, inverse, "symmetric", transitive, deprecated_by, from_types, to_types, description)
VALUES
('source', 'source-of', false, true, NULL, NULL, NULL,
 'The piece of information this one is sourced from'),

('derived-from', NULL, false, true, 'source', NULL, NULL,
 'The information this content was derived from'),

('supersedes', 'superseded-by', false, true, NULL, NULL, NULL,
 'Invalidates a previous decision'),

('part-of', 'has-part', false, false, NULL, NULL, ARRAY['project'],
 'Part of a project'),

('progress-next', 'progress-prev', false, false, NULL,
 ARRAY['task'], ARRAY['task'],
 'The next step in a task sequence'),

('implements', 'implemented-by', false, false, NULL,
 ARRAY['task'], ARRAY['decision'],
 'The task that carries out a decision'),

('resolves', 'resolved-by', false, false, NULL,
 ARRAY['task'], ARRAY['blocker'],
 'The task that resolves a blocker'),

('contradicts', NULL, true, false, NULL, NULL, NULL,
 'Information that contradicts another piece of information');

INSERT INTO node (id, type, title, props)
VALUES
('d00', 'project', 'Project: Mobile v2 launch',
 '{"owner": "ayse"}'),

('d01', 'message', 'Slack: Payment SDK crashes on iOS',
 '{"author": "mehmet", "date": "2026-09-14"}'),

('d02', 'meeting', 'Weekly sync meeting',
 '{"date": "2026-09-15"}'),

('d03', 'blocker', 'Blocker: Payment crash on iOS',
 '{}'),

('d04', 'decision', 'Decision: Upgrade to SDK v4',
 '{"date": "2026-09-15"}'),

('d05', 'task', 'Task: SDK v4 integration',
 '{"status": "done", "owner": "mehmet"}'),

('d06', 'task', 'Task: iOS regression testing',
 '{"status": "in-progress", "owner": "ayse"}'),

('d07', 'task', 'Task: Submit to the App Store',
 '{"status": "todo"}'),

('d08', 'decision', 'Decision: Stay on Payment SDK v3',
 '{"date": "2026-09-01"}'),

('d09', 'ai-summary', 'MrBrief: Weekly status summary',
 '{"date": "2026-09-17", "generated-by": "ai-assistant"}'),

('d10', 'message', 'Slack: SDK v4 causes slowness on Android',
 '{"author": "ayse", "date": "2026-09-18"}');

INSERT INTO edge (from_id, rel_type, to_id, props)
VALUES
('d03', 'derived-from', 'd01', '{}'),
('d03', 'source', 'd02', '{}'),
('d04', 'source', 'd03', '{}'),
('d04', 'source', 'd02', '{}'),
('d04', 'supersedes', 'd08', '{}'),
('d04', 'part-of', 'd00', '{}'),
('d05', 'part-of', 'd00', '{}'),
('d06', 'part-of', 'd00', '{}'),
('d07', 'part-of', 'd00', '{}'),
('d05', 'implements', 'd04', '{}'),
('d05', 'resolves', 'd03', '{}'),
('d05', 'progress-next', 'd06', '{}'),
('d06', 'progress-next', 'd07', '{}'),
('d09', 'source', 'd04', '{"confidence": 0.9}'),
('d09', 'source', 'd05', '{"confidence": 0.8}'),
('d10', 'contradicts', 'd09',
 '{"by": "ayse", "date": "2026-09-18"}');
