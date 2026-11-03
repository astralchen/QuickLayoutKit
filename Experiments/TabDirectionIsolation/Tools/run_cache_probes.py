"""Run opt-in private-cache timing experiments in the standalone diagnostic app."""
import argparse, json, subprocess, time, pathlib, shutil
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator', required=True)
parser.add_argument('--app', required=True)
parser.add_argument('--output', required=True, type=pathlib.Path)
parser.add_argument('--article-only', action='store_true', help='Compare native UITab with/without clearing the legacy item; never call private setters.')
parser.add_argument('--semantics-only', action='store_true', help='Compare unspecified semantics with a directional window versus trait overrides only; no private setters.')
args = parser.parse_args()
if args.article_only and args.semantics_only:
    parser.error('Choose only one comparison mode.')
sim = args.simulator
bundle = 'com.quicklayoutkit.TabDirectionIsolation'
out = args.output
out.mkdir(parents=True, exist_ok=True)
def ctl(*args):
    return subprocess.check_output(['xcrun','simctl',*args],text=True).strip()
ctl('install', sim, args.app)
data=pathlib.Path(ctl('get_app_container',sim,bundle,'data'))
cases=[('none',False,False),('before',False,False),('after',False,False),('late',False,False),('before',True,False),('after',True,False),('before',True,True),('before',False,True),('after',False,True)]
if args.article_only or args.semantics_only:
    cases = [('none', False, True), ('none', False, True)]
summary=[]
for case_index, (mode,rtl,modern) in enumerate(cases):
    clear_items = args.article_only and case_index == 1
    name=f'cache-{mode}-{"rtl" if rtl else "ltr"}-{"modern" if modern else "legacy"}'
    src=data/'tmp'/(name+'.json')
    src.unlink(missing_ok=True)
    launch_args=['--cache='+mode]+(['--initial-rtl'] if rtl else [])+(['--modern-tabs'] if modern else [])
    if clear_items: launch_args.append('--clear-legacy-items')
    semantics = ('inherited', 'traits')[case_index] if args.semantics_only else 'explicit'
    if args.semantics_only: launch_args.append('--semantics=' + semantics)
    ctl('launch','--terminate-running-process',sim,bundle,*launch_args)
    deadline=time.monotonic()+45
    while not src.exists() and time.monotonic()<deadline: time.sleep(.3)
    if not src.exists(): raise RuntimeError('Missing result '+name)
    raw=json.loads(src.read_text())
    if clear_items: name += '-clear-items'
    if args.semantics_only: name += '-' + semantics
    shutil.copyfile(src, out / (name + '.json'))
    stages=[]
    for s in raw['snapshots']:
        if s['name'].endswith(('immediate','layout')): continue
        cs=[v for v in s['views'] if v['class']=='_UIFloatingTabBarCollectionView']
        labels=[v for v in s['views'] if '_UIFloatingTabBarCollectionView/' in v['path'] and v['text'] in ['Alpha','Beta','Gamma','示例','الأمثلة']]
        inputs=[v for v in s['views'] if v['accessibilityID']=='cache-probe.input']
        stages.append({'stage':s['name'],'root':s['tabs'],'navigation':s['navigation'],'bar':s['tabBarView'],'trait':s['tabControllerTrait'],'modernTabState':s['modernTabState'],'collections':[{'id':v['id'],'layout':v['collectionLayout']['id'],'cacheRTL':v['collectionLayout']['diagnosticLayoutRTL'],'axis':v['diagnosticHorizontalAxisFlip'],'effective':v['effectiveDirection'],'trait':v['traitDirection']} for v in cs],'labels':[{'text':v['text'],'axisX':v['toWindow'][2],'originX':v['toWindow'][0]} for v in labels],'inputs':[{k:v[k] for k in ['id','inputText','firstResponder','selection']} for v in inputs]})
    result={'case':name,'os':raw['os'],'writes':raw['cacheWrites'],'semantics':raw.get('semantics', 'explicit'),'stages':stages}
    summary.append(result)
    (out/'cache-results.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n')
    bad=[s['stage'] for s in stages if len(s['labels'])!=3 or any(v['axisX']!=10 for v in s['labels'])]
    focus=all(len(s['inputs'])==1 and s['inputs'][0]['firstResponder'] for s in stages)
    print(name,'bad-label-stages=',bad,'focus=',focus,'writes=',len(raw['cacheWrites']),flush=True)
