#!/usr/bin/env python3
"""Run the expanded feature corpus against authenticated LTPRO captures.

Reviewed differences are exact, explained Lua expectations, never replacement
oracle output. Unexpected results and execution failures always fail the run.
Use --strict-oracle to fail on every difference from the executable.
"""
import argparse
import json
from pathlib import Path

from ltpro_pipeline_probe import run_lua, validate


CORPORA = (
    ('cases.json', 'reference.json'),
    ('phrase-cases.json', 'phrase-reference.json'),
    ('natural-cases.json', 'natural-reference.json'),
    ('control-cases.json', 'control-reference.json'),
)


def classify(status, actual, oracle, review=None):
    expected = review['expected_lua'] if review else oracle
    if status != 'OK':
        return 'errors'
    if actual != expected:
        return 'unexpected'
    if actual == oracle:
        return 'exact'
    return review['classification']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, default=Path('test/ltpro/review-2026-10-08'))
    parser.add_argument('--data', type=Path, default=Path('LTGOLD'))
    parser.add_argument('--lua', default='lua')
    parser.add_argument('--report', type=Path)
    parser.add_argument('--strict-oracle', action='store_true')
    args = parser.parse_args()
    cases, provenance, seen = [], [], set()
    for inputs, reference in CORPORA:
        _, captured, errors, reference_hash, input_hash = validate(
            args.corpus / reference, args.corpus / inputs, args.data)
        if errors:
            raise SystemExit(f'{reference}: INVALID PROVENANCE: ' + '; '.join(errors))
        for case in captured:
            if case['id'] in seen:
                raise SystemExit('duplicate case ID: ' + case['id'])
            seen.add(case['id'])
        cases.extend(captured)
        provenance.append(dict(reference=reference, reference_sha256=reference_hash,
                               cases=inputs, cases_sha256=input_hash))
    review_path = args.corpus / 'reviewed-differences.json'
    reviews = json.loads(review_path.read_text()) if review_path.exists() else {}
    unknown = set(reviews) - seen
    if unknown:
        raise SystemExit('reviewed IDs absent from corpus: ' + ', '.join(sorted(unknown)))
    for case in cases:
        entry = reviews.get(case['id'])
        if entry and (not entry.get('reason') or
                      entry.get('classification') not in ('intentional_difference', 'known_limitation') or
                      entry.get('oracle_raw_sha256') != case['raw_sha256'] or
                      not isinstance(entry.get('expected_lua'), str)):
            raise SystemExit('invalid or stale review: ' + case['id'])

    report = dict(total=len(cases), exact=0, intentional_difference=0,
                  known_limitation=0, unexpected=0, errors=0,
                  provenance=provenance, cases=[])
    for expected_index, (case, (index, status, actual)) in enumerate(
            zip(cases, run_lua(cases, args.data.resolve(), args.lua)), 1):
        if index != expected_index:
            raise SystemExit('Lua result order mismatch')
        review = reviews.get(case['id'])
        classification = classify(status, actual, case['translation'], review)
        report[classification] += 1
        row = dict(id=case['id'], group=case['group'], input=case['input'],
                   ltpro=case['translation'], lua=actual, classification=classification,
                   reason=review['reason'] if review else None)
        report['cases'].append(row)
        if classification in ('errors', 'unexpected'):
            print(f'{classification.upper()} {case["id"]}: {case["input"]}\n'
                  f'  LTPRO: {case["translation"]}\n  Lua:   {actual}', flush=True)
    print('Feature review: ' + ' '.join(f'{key.upper()}={report[key]}' for key in
          ('total', 'exact', 'intentional_difference', 'known_limitation', 'unexpected', 'errors')))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit(bool(report['unexpected'] or report['errors'] or
                         args.strict_oracle and report['exact'] != report['total']))


if __name__ == '__main__':
    main()
