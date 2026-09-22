-- Q1: Which decision is currently in effect?
SELECT id, title
FROM node n
WHERE type = 'decision'
  AND NOT EXISTS (
    SELECT 1
    FROM edge_v
    WHERE rel = 'supersedes'
      AND to_id = n.id
  );

-- Q2: What sources does the AI summary (d09) rely on?
WITH RECURSIVE origins(id) AS (
  SELECT to_id
  FROM edge_v
  WHERE from_id = 'd09'
    AND rel = 'source'
  UNION
  SELECT e.to_id
  FROM edge_v e
  JOIN origins o ON e.from_id = o.id
  WHERE e.rel = 'source'
)
SELECT o.id, n.title
FROM origins o
JOIN node n ON n.id = o.id
ORDER BY o.id;

-- Q3: What is affected if d01 turns out to be wrong? (impact analysis)
WITH RECURSIVE affected(id) AS (
  SELECT from_id
  FROM edge_v
  WHERE to_id = 'd01'
    AND rel = 'source'
  UNION
  SELECT e.from_id
  FROM edge_v e
  JOIN affected a ON e.to_id = a.id
  WHERE e.rel = 'source'
)
SELECT a.id, n.type, n.title
FROM affected a
JOIN node n ON n.id = a.id
ORDER BY a.id;


-- Q4: What tasks come after d05?
WITH RECURSIVE sequence(id, step) AS (
  SELECT to_id, 1
  FROM edge_v
  WHERE from_id = 'd05'
    AND rel = 'progress-next'
  UNION ALL
  SELECT e.to_id, s.step + 1
  FROM edge_v e
  JOIN sequence s ON e.from_id = s.id
  WHERE e.rel = 'progress-next'
    AND s.step < 50
)

SELECT s.step, n.id, n.title, n.props ->> 'status' AS status
FROM sequence s
JOIN node n ON n.id = s.id
ORDER BY s.step;

-- Q5: Which AI summary has been disputed, and by whom?
SELECT
  s.id AS summary,
  o.id AS dispute,
  o.title,
  c.props
FROM node s
JOIN edge_v c
  ON c.rel = 'contradicts'
 AND s.id IN (c.from_id, c.to_id)
JOIN node o
  ON o.id = CASE
              WHEN c.from_id = s.id THEN c.to_id
              ELSE c.from_id
            END
WHERE s.type = 'ai-summary';
