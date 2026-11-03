"""Compare direction propagation, update ordering, and pre-transition presentation paths.

Only app-owned public API mutations select the candidate. Runtime getters and a
later native layout invalidation are diagnostic instrumentation, not a shipping fix.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time


def summarize(raw, case):
    stages = []
    for snapshot in raw['snapshots']:
        if snapshot['name'].endswith(('immediate', 'layout')):
            continue
        views = snapshot['views']
        collections = [v for v in views if v['class'] == '_UIFloatingTabBarCollectionView']
        labels = [v for v in views if '_UIFloatingTabBarCollectionView/' in v['path']
                  and v['text'] in ['Alpha', 'Beta', 'Gamma', '示例', 'الأمثلة']]
        inputs = [v for v in views if v['accessibilityID'] == 'cache-probe.input']
        stages.append({
            'stage': snapshot['name'], 'root': snapshot['tabs'],
            'navigation': snapshot['navigation'], 'bar': snapshot['tabBarView'],
            'trait': snapshot['tabControllerTrait'], 'windowTrait': snapshot['windowTrait'],
            'sceneTrait': snapshot['sceneTrait'], 'models': snapshot['modernTabState'],
            'collections': [{'id': v['id'], 'layout': v['collectionLayout']['id'],
                             'cacheRTL': v['collectionLayout']['diagnosticLayoutRTL'],
                             'axis': v['diagnosticHorizontalAxisFlip'],
                             'effective': v['effectiveDirection'], 'trait': v['traitDirection'],
                             'hidden': v['hidden'], 'frame': v['frame']} for v in collections],
            'labels': [{'text': v['text'], 'axisX': v['toWindow'][2],
                        'originX': v['toWindow'][0]} for v in labels],
            'inputs': [{k: v[k] for k in ['id', 'inputText', 'firstResponder', 'selection', 'hasMarkedText']}
                       for v in inputs],
        })
    stable = [s for s in stages if '-presentation-' not in s['stage']]
    failures = []
    for s in stable:
        index = int(s['stage'].split('-')[0])
        rtl = (index % 2 == 0) if raw['initialRTL'] else (index % 2 == 1)
        reasons = []
        if s['trait'] != int(rtl): reasons.append('controller-direction')
        if len(s['collections']) != 1: reasons.append('native-collection-count')
        for cv in s['collections']:
            if cv['effective'] != int(rtl) or cv['trait'] != int(rtl): reasons.append('collection-direction')
            if cv['cacheRTL'] != rtl: reasons.append('stale-cache')
            if cv['axis'] != rtl: reasons.append('axis-flip')
        if len(s['labels']) != 3 or any(v['axisX'] != 10 for v in s['labels']): reasons.append('label-mirror-or-missing')
        labels = sorted(s['labels'], key=lambda v: {'Beta': 1, 'Gamma': 2}.get(v['text'], 0))
        xs = [v['originX'] for v in labels]
        if xs != sorted(xs, reverse=rtl): reasons.append('tab-order')
        if reasons: failures.append({'stage': s['stage'], 'reasons': reasons})
    first = stages[0]
    identities = all(s[k] == first[k] for s in stages for k in ['root', 'navigation', 'bar', 'models'])
    same_controllers = all(s[k] == first[k] for s in stages for k in ['root', 'navigation', 'bar'])
    same_pages = all(s['models'].get(k) == stable[0]['models'].get(k) for s in stable for k in ['page', 'selectedController'])
    preserve_required = same_controllers and same_pages and (identities or raw['presentation'].startswith('fresh-'))
    inputs = [s['inputs'][0] for s in stages if len(s['inputs']) == 1]
    focus = len(inputs) == len(stages) and all(v['firstResponder'] for v in inputs)
    input_identity = len({v['id'] for v in inputs}) == 1
    draft = all(len(s['inputs']) == 1 and s['inputs'][0]['inputText'] ==
                '草稿 Draft مسودة' + '续' * (int(s['stage'].split('-')[0]) + 1)
                for s in stable if s['stage'].endswith('cache-final'))
    return {
        'case': case, 'os': raw['os'],
        'configuration': {k: raw[k] for k in ['directionSource', 'timing', 'presentation', 'semantics', 'initialRTL']},
        'privateSetterCalls': len(raw['cacheWrites']), 'stableSamples': len(stable),
        'directionAndGeometryFailures': failures, 'sameControllerBarAndModels': identities,
        'replacementBlocked': raw.get('replacementBlocked', False),
        'replacementEvents': raw.get('replacementEvents', []),
        'sameControllerAndBar': same_controllers, 'sameSelectedControllerAndPage': same_pages,
        'sameInput': input_identity, 'sampledFocusPreserved': focus, 'draftPreserved': draft,
        'stableLayoutIdentities': sorted({cv['layout'] for s in stable for cv in s['collections']}),
        'candidatePassed': len(stable) == 36 and not failures and preserve_required and input_identity and focus and draft,
        'stages': stages,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--app', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--fresh-tabs-only', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    bundle = 'com.quicklayoutkit.TabDirectionIsolation'
    def ctl(*command):
        return subprocess.check_output(['xcrun', 'simctl', *command], text=True).strip()
    ctl('install', args.simulator, args.app)
    data = Path(ctl('get_app_container', args.simulator, bundle, 'data'))
    cases = [(source, 'settled', 'none') for source in ['controller', 'window', 'scene']]
    cases += [(source, timing, 'none') for source in ['controller', 'scene']
              for timing in ['before', 'direction-layout', 'next-turn', 'atomic']]
    cases += [(source, 'atomic', presentation) for source in ['controller', 'scene']
              for presentation in ['hide', 'sidebar', 'compact']]
    if args.fresh_tabs_only:
        cases = [('scene', 'atomic', p) for p in ['fresh-tabs', 'fresh-identifiers']]
    results = []
    for source, timing, presentation in cases:
        name = '-'.join([source, timing, presentation])
        src = data / 'tmp/cache-none-ltr-modern.json'
        src.unlink(missing_ok=True)
        ctl('launch', '--terminate-running-process', args.simulator, bundle, '--modern-tabs', '--cache=none',
            '--semantics=traits', '--direction-source=' + source, '--timing=' + timing, '--presentation=' + presentation)
        deadline = time.monotonic() + 60
        while not src.exists() and time.monotonic() < deadline: time.sleep(.3)
        if not src.exists(): raise RuntimeError('Missing result: ' + name)
        raw = json.loads(src.read_text())
        assert not raw['cacheWrites'], 'This matrix must never call a private setter.'
        assert (raw['directionSource'], raw['timing'], raw['presentation']) == (source, timing, presentation)
        shutil.copyfile(src, args.output / (name + '.json'))
        result = summarize(raw, name)
        results.append(result)
        (args.output / 'public-matrix-results.json').write_text(json.dumps(results, indent=2, ensure_ascii=False) + '\n')
        print(name, 'candidatePassed=', result['candidatePassed'],
              'badStableStages=', len(result['directionAndGeometryFailures']),
              'focus=', result['sampledFocusPreserved'], 'draft=', result['draftPreserved'],
              'layoutCount=', len(result['stableLayoutIdentities']), flush=True)


if __name__ == '__main__':
    main()
