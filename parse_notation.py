#!/usr/bin/env python3
"""Parse the case notation into PostgreSQL node and edge tables.

Supported notation:
- Title
  id:: d01
  type:: message
  property:: value
  relation:: d02
  relation:: d03 {confidence: 0.9}
  relation:: d04, d05

A relation is recognized from rel_type.name. Other keys become node properties.
"""
import argparse, json, re
from collections import defaultdict
from pathlib import Path

BLOCK_RE = re.compile(r"(?m)^- (.*?)(?=^\n?- |\Z)", re.S)
PROP_RE = re.compile(r"^\s*([A-Za-z][A-Za-z0-9_-]*)::\s*(.*?)\s*$")
TARGET_RE = re.compile(r"^([^{}]+?)(?:\s*\{(.*)\})?$")
META_RE = re.compile(r"\s*([A-Za-z][A-Za-z0-9_-]*)\s*:\s*([^,]+)\s*(?:,|$)")


def split_values(value):
    parts, current, depth = [], [], 0
    for ch in value:
        if ch == '{': depth += 1
        elif ch == '}': depth -= 1
        if ch == ',' and depth == 0:
            if ''.join(current).strip(): parts.append(''.join(current).strip())
            current = []
        else: current.append(ch)
    if ''.join(current).strip(): parts.append(''.join(current).strip())
    return parts


def parse_meta(text):
    return {m.group(1): m.group(2).strip() for m in META_RE.finditer(text or '')}


def parse(path, relation_names):
    nodes, edges = [], []
    text = Path(path).read_text(encoding='utf-8')
    for raw in BLOCK_RE.finditer(text):
        lines = raw.group(1).splitlines()
        title = lines[0].strip()
        props = {}
        for line in lines[1:]:
            match = PROP_RE.match(line)
            if match: props[match.group(1)] = match.group(2)
        node_id, node_type = props.pop('id', None), props.pop('type', None)
        if not node_id or not node_type:
            raise ValueError(f"Block {title!r} requires id:: and type::")
        node_props = {}
        for key, value in props.items():
            if key in relation_names:
                for item in split_values(value):
                    m = TARGET_RE.match(item)
                    target, metadata = m.group(1).strip(), parse_meta(m.group(2))
                    edges.append({'from_id': node_id, 'rel_type': key, 'to_id': target, 'props': metadata})
            else:
                node_props[key] = value
        nodes.append({'id': node_id, 'type': node_type, 'title': title, 'props': node_props})
    return nodes, edges


def sql_literal(value):
    return "'" + value.replace("'", "''") + "'"


def write_sql(nodes, edges, path):
    lines = ['BEGIN;', 'TRUNCATE edge, node RESTART IDENTITY CASCADE;']
    for n in nodes:
        lines.append("INSERT INTO node (id, type, title, props) VALUES (%s, %s, %s, %s::jsonb);" % (
            sql_literal(n['id']), sql_literal(n['type']), sql_literal(n['title']), sql_literal(json.dumps(n['props'], ensure_ascii=False))))
    for e in edges:
        lines.append("INSERT INTO edge (from_id, rel_type, to_id, props) VALUES (%s, %s, %s, %s::jsonb);" % (
            sql_literal(e['from_id']), sql_literal(e['rel_type']), sql_literal(e['to_id']), sql_literal(json.dumps(e['props'], ensure_ascii=False))))
    lines += ['COMMIT;', '']
    Path(path).write_text('\n'.join(lines), encoding='utf-8')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('notation')
    ap.add_argument('--relations', default='source,derived-from,supersedes,part-of,progress-next,implements,resolves,contradicts')
    ap.add_argument('--output', default='load_generated.sql')
    args = ap.parse_args()
    nodes, edges = parse(args.notation, set(args.relations.split(',')))
    write_sql(nodes, edges, args.output)
    print(f'Parsed {len(nodes)} nodes and {len(edges)} edges -> {args.output}')

if __name__ == '__main__': main()
