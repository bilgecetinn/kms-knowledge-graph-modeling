#!/usr/bin/env python3
"""Export the PostgreSQL property graph to RDF Turtle.

Requires: pip install psycopg2-binary rdflib
"""
import argparse, json
import psycopg2
from rdflib import Graph, Namespace, URIRef, Literal
from rdflib.namespace import RDF, XSD


def uri(ns, value): return URIRef(ns + str(value))

def literal(value):
    if isinstance(value, bool): return Literal(value)
    if isinstance(value, (int, float)): return Literal(value)
    return Literal(str(value))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--database', default='kms_test')
    ap.add_argument('--host', default='localhost')
    ap.add_argument('--port', default=5432, type=int)
    ap.add_argument('--user', default=None)
    ap.add_argument('--password', default=None)
    ap.add_argument('--base', default='https://example.org/kms/')
    ap.add_argument('--output', default='graph.ttl')
    args = ap.parse_args()
    conn = psycopg2.connect(dbname=args.database, host=args.host, port=args.port, user=args.user, password=args.password)
    g = Graph(); K = Namespace(args.base); g.bind('kms', K)
    with conn.cursor() as cur:
        cur.execute('SELECT id, type, title, body, props FROM node ORDER BY id')
        for node_id, typ, title, body, props in cur.fetchall():
            subject = uri(K, 'node/' + node_id)
            g.add((subject, RDF.type, uri(K, 'type/' + typ)))
            g.add((subject, K.title, Literal(title)))
            if body: g.add((subject, K.body, Literal(body)))
            for key, value in (props or {}).items(): g.add((subject, uri(K, 'property/' + key), literal(value)))
        cur.execute('SELECT from_id, rel_type, to_id, props FROM edge ORDER BY id')
        for source, rel, target, props in cur.fetchall():
            s, p, o = uri(K, 'node/' + source), uri(K, 'relation/' + rel), uri(K, 'node/' + target)
            g.add((s, p, o))
            for key, value in (props or {}).items():
                g.add((URIRef(f'{s}#edge-{rel}-{target}'), uri(K, 'edge-property/' + key), literal(value)))
    g.serialize(destination=args.output, format='turtle')
    conn.close(); print(f'Wrote {len(g)} triples to {args.output}')

if __name__ == '__main__': main()
