"""Read-only coverage/source gate. Passing coverage is not animation completion."""
from pathlib import Path
import argparse
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
SLOTS = {'attack', 'skill_1', 'skill_2', 'ultimate', 'hit', 'guard', 'down', 'settlement'}
NAMES = {'凛零', '梅林', '墨华', '冰糖', '安克', '卡斯特', '茧'}


def check(verify_sources=False, require_ready=False):
    data = json.loads((ROOT / 'docs/party-animation-manifest.json').read_text('utf-8'))
    audit = json.loads((ROOT / data['source_audit']).read_text('utf-8'))
    assert data['schema_version'] == 1, 'unsupported manifest version'
    assert data['scope']['enemy_animations'] == 'deferred', 'enemy scope changed without decision'
    assert data['scope']['idle_required_for_all_actors_and_forms'], 'global idle requirement lost'
    assert all(c.get('idle_required') for c in data['other_source_characters']), 'non-sin actor missing required idle'
    assert {s['id'] for s in data['action_slots']} == SLOTS
    actors = data['confirmed_seven_sins']
    assert len(actors) == 7 and {a['name'] for a in actors} == NAMES, 'seven-sins coverage mismatch'
    assert len({a['id'] for a in actors}) == 7, 'duplicate actor id'
    sources = {(e['pointer'], e['id'], e['sha256']) for c in audit['characters'] for e in c['entries']}
    clips, support, ids = [], [], set()

    def source(entry):
        assert (entry['pointer'], entry['id'], entry['sha256']) in sources, 'untraced character entry'

    def clip(item):
        assert item['clip_id'] not in ids, 'duplicate clip id'
        ids.add(item['clip_id'])
        assert item['status'] in {'not_started', 'draft', 'ready_for_review', 'accepted'}, 'unknown status'
        if item['status'] == 'accepted':
            assert item['visual_acceptance'] == 'driver-accepted' and item.get('acceptance_evidence'), 'acceptance without evidence'
            assert item.get('personality_acceptance') in {'review-pass', 'driver-accepted'}, 'accepted clip lacks personality review'
            for key in ('source_asset', 'runtime_asset'):
                path = (ROOT / item[key]).resolve()
                assert path.is_relative_to(ROOT) and path.is_file(), 'accepted asset missing or outside project'
        return item

    for actor in actors:
        assert actor.get('personality_profile') == actor['id'], 'missing actor personality profile'
        assert set(actor['forms']) == {'base', 'released'}, 'missing independent form'
        for form_id, form in actor['forms'].items():
            assert form['id'] == form_id and set(form['actions']) == SLOTS, 'incomplete form action set'
            source(form['source_entry'])
            assert form['reference']['exists'], 'missing illustration reference'
            for slot, item in form['actions'].items():
                assert item['clip_id'] == f"{actor['id']}.{form_id}.{slot}", 'clip binding mismatch'
                clips.append(clip(item))
            assert set(form['support']) == {'idle'}, 'missing idle support'
            support.append(clip(form['support']['idle']))
        transition = actor['transformation']
        assert transition['action_id'] == 'liberate' and transition['from_form'] == 'base' and transition['to_form'] == 'released'
        source(transition['source_entry'])
        clips.append(clip(transition))
    assert len(clips) == 119 and len(support) == 14
    assert data['current_study']['counts_as_completed_action'] is False, 'unapproved study counted as complete'
    ming = next(c for c in data['other_source_characters'] if c['name'] == '明空')
    assert ming['scope_status'] == 'support_design_authorized' and ming['gameplay_role'] == 'support', 'approved support direction lost'
    policies = data['game_adaptations']
    assert policies['flying_star']['design_allowed'] and policies['descent']['design_allowed'], 'latest user ability authorization lost'
    assert policies['descent']['scope'] == 'game-only' and policies['support_roles']['design_allowed'], 'game adaptation boundary lost'
    verified_files = 0
    if verify_sources:
        references = audit['sources'] + [art for c in audit['characters'] for art in c['art'] if art.get('exists')]
        for ref in references:
            path = Path(ref['path'])
            assert path.is_file(), f'source missing: {path}'
            assert hashlib.sha256(path.read_bytes()).hexdigest() == ref['sha256'], f'source changed; re-audit: {path}'
            verified_files += 1
    completed = sum(c['status'] == 'accepted' for c in clips)
    if require_ready:
        assert completed == len(clips) and all(c['status'] == 'accepted' for c in support), 'party animations are not production-ready'
    return {'requirements_structure_pass': True, 'source_files_verified': verified_files,
            'planned_primary_clips': len(clips), 'completed_primary_clips': completed,
            'planned_required_clips': len(clips) + len(support), 'completed_required_clips': completed + sum(c['status'] == 'accepted' for c in support),
            'planned_idle_clips': len(support), 'completed_idle_clips': sum(c['status'] == 'accepted' for c in support),
            'note': 'Coverage and provenance gate only; no new animation or gameplay has been implemented.'}


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-sources', action='store_true')
    parser.add_argument('--require-ready', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(check(args.verify_sources, args.require_ready), ensure_ascii=False, indent=2))
    except (AssertionError, KeyError, ValueError, TypeError, OSError) as error:
        print(f'REJECTED: {error}', file=sys.stderr)
        raise SystemExit(1)
