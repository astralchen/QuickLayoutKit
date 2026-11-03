"""Run isolated public recovery candidates on an already booted iPad simulator."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time

CASES = ('idiom', 'compact-idiom', 'sidebar', 'hide', 'items', 'appearance',
         'batch', 'minimize', 'content-size', 'tabs-assign', 'tabs-set', 'tabs-animated',
         'tabs-empty', 'tabs-reorder', 'tabs-remove-unselected', 'tabs-reselect')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--cases', nargs='+', choices=CASES, default=CASES)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    bundle = 'com.quicklayoutkit.TabDirectionIsolation'
    def simctl(*command):
        return subprocess.check_output(['xcrun', 'simctl', *command], text=True).strip()
    simctl('install', args.simulator, str(args.app))
    data = Path(simctl('get_app_container', args.simulator, bundle, 'data'))
    summary = []
    for case in args.cases:
        source = data / 'tmp' / ('recovery-' + case + '.json')
        if source.exists():
            source.unlink()
        simctl('launch', '--terminate-running-process', args.simulator, bundle, '--recovery=' + case)
        deadline = time.monotonic() + 30
        while not source.exists() and time.monotonic() < deadline:
            time.sleep(.3)
        if not source.exists():
            raise RuntimeError('No result for ' + case)
        evidence = json.loads(source.read_text())
        shutil.copyfile(source, args.output / source.name)
        stages = []
        for snapshot in evidence['snapshots']:
            if not snapshot['name'].endswith(('settled', 'recovered', 'stress')):
                continue
            collections = [v for v in snapshot['views'] if v['class'] == '_UIFloatingTabBarCollectionView']
            stages.append({
                'stage': snapshot['name'], 'root': snapshot['tabs'],
                'trait': snapshot['tabControllerTrait'],
                'modernTabState': snapshot.get('modernTabState', {}),
                'collections': [{'id': v['id'], 'layout': v['collectionLayout']['id'],
                                 'layoutRTL': v['collectionLayout']['diagnosticLayoutRTL'],
                                 'axisFlip': v['diagnosticHorizontalAxisFlip']} for v in collections],
                'labelAxes': [v['toWindow'][2] for v in snapshot['views'] if v['text'] == 'Alpha'],
            })
        summary.append({'case': case, 'stages': stages})
        (args.output / 'public-recovery-results.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(case, [(s['stage'], s['labelAxes']) for s in stages if s['stage'].endswith(('recovered', 'stress'))], flush=True)

if __name__ == '__main__':
    main()
