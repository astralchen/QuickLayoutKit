"""LLDB breakpoint logging for the isolated arm64 simulator app; no private setters invoked.
Import this module, run `trace-flips /absolute/output.jsonl`, then continue the app
launched with --debug-pause. Expressions only read state at existing UIKit calls.
"""
import json
import time
import lldb

_output = None

def _value(frame, expression):
    result = frame.EvaluateExpression(expression)
    return result.GetValue() if result.GetError().Success() else str(result.GetError())

def sample(frame, bp_loc, internal_dict):
    obj = hex(frame.FindRegister('x0').GetValueAsUnsigned())
    function = frame.GetFunctionName() or ''
    is_layout = 'setLayoutRTL:' in function
    collection = ('[(id)' + obj + ' collectionView]') if is_layout else ('(id)' + obj)
    layout = ('(id)' + obj) if is_layout else ('[' + collection + ' collectionViewLayout]')
    event = {
        'time': time.time(), 'function': function, 'object': obj,
        'setterArgument': frame.FindRegister('x2').GetValueAsUnsigned() if 'set' in function.lower() else None,
        'effectiveDirection': _value(frame, '(long)[' + collection + ' effectiveUserInterfaceLayoutDirection]'),
        'traitDirection': _value(frame, '(long)[[' + collection + ' traitCollection] layoutDirection]'),
        'layoutRTLBefore': _value(frame, '(BOOL)[' + layout + ' layoutRTL]'),
        'axisFlipBefore': _value(frame, '(BOOL)[' + collection + ' _flipsHorizontalAxis]'),
        'stack': [f.GetFunctionName() for f in frame.GetThread()][:18],
    }
    with open(_output, 'a') as stream:
        stream.write(json.dumps(event) + '\n')
    print('FLIP_TRACE', function, event['setterArgument'], event['effectiveDirection'], event['layoutRTLBefore'])
    return False

def install(debugger, command, result, internal_dict):
    global _output
    _output = command.strip()
    if not _output.startswith('/'):
        result.SetError('Provide an absolute output path.')
        return
    open(_output, 'w').close()
    target = debugger.GetSelectedTarget()
    for name, class_name in [
        ('-[UIView _setFlipsHorizontalAxis:]', '_UIFloatingTabBarCollectionView'),
        ('-[UICollectionView _layoutDirectionTraitDidChange]', '_UIFloatingTabBarCollectionView'),
        ('-[UICollectionViewCompositionalLayout setLayoutRTL:]', '_UIFloatingTabBarCollectionViewLayout'),
    ]:
        bp = target.BreakpointCreateByName(name)
        bp.SetCondition('(BOOL)[(id)$x0 isKindOfClass:NSClassFromString(@"' + class_name + '")]')
        bp.SetScriptCallbackFunction(__name__ + '.sample')
    result.AppendMessage('Trace installed: ' + _output)

def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand('command script add -f ' + __name__ + '.install trace-flips')
