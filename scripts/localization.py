#!/usr/bin/env python3
"""Validate source-key translations and render deterministic addon-owned Lua tables."""
import argparse, ast, hashlib, json, re
from pathlib import Path
import sys
sys.dont_write_bytecode = True

LOCALES = {'deDE':'German', 'frFR':'French', 'esES':'European Spanish', 'esMX':'Latin American Spanish', 'ptBR':'Brazilian Portuguese', 'ruRU':'Russian', 'itIT':'Italian', 'koKR':'Korean', 'zhCN':'Simplified Chinese', 'zhTW':'Traditional Chinese'}
LITERAL = r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' '''.strip()
LOOKUP = re.compile(r'\bL\(\s*('+LITERAL+r')\s*\)')
FORMAT = re.compile(r'%(?:[-+ #0]*\d*(?:\.\d+)?[cdiouxXeEfgGqs%])')

def dumps(value): return json.dumps(value,ensure_ascii=False,indent=2)+'\n'
def digest(notes):
    return hashlib.sha256(json.dumps({k:v for k,v in notes.items() if k!='version'},sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
def quote(text):
    return json.dumps(text,ensure_ascii=False).replace('\\b','\\008').replace('\\f','\\012')
def lua(value):
    if isinstance(value,str): return quote(value)
    if isinstance(value,list): return '{'+','.join(lua(v) for v in value)+'}'
    if isinstance(value,dict): return '{'+','.join('['+quote(k)+']='+lua(v) for k,v in sorted(value.items()))+'}'
    raise ValueError('unsupported Lua translation value')
def read(path):
    def unique(pairs):
        out={}
        for k,v in pairs:
            if k in out: raise ValueError('duplicate translation key: '+k)
            out[k]=v
        return out
    return json.loads(path.read_text(),object_pairs_hook=unique)
def source_strings(root):
    keys=set()
    for p in root.glob('*.lua'):
        if p.name in ('Tests.lua','Locales.lua','LocalizedReleaseNotes.lua','ReleaseNotes.lua'): continue
        for m in LOOKUP.finditer(p.read_text()): keys.add(ast.literal_eval(m[1]))
    # Dynamic, canonical status identifiers are translated only at presentation.
    keys.update(read(root/'locales/dynamic.json'))
    return sorted(keys)
def validate_translation(source,target):
    if not isinstance(target,str) or not target.strip(): raise ValueError('empty translation: '+source)
    if FORMAT.findall(source):
        position=0
        while True:
            position=target.find('%',position)
            if position<0:break
            match=FORMAT.match(target,position)
            if not match:raise ValueError('invalid format token: '+source)
            position=match.end()
    commands = r'/qtd?\b(?: [a-z]+)?'
    if re.findall(commands,source)!=re.findall(commands,target):raise ValueError('command changed: '+source)
    for argument in re.findall(r'<[^>]+>|\[(?:on|questID)[^\]]*\]|emoteOnQuestCompletion|on\|off\|toggle|true/false, on/off, 1/0',source):
        if '/qt' in source and argument not in target:raise ValueError('command argument changed: '+source)
    if FORMAT.findall(source)!=FORMAT.findall(target): raise ValueError('format placeholders differ: '+source)
    if re.match(r'^\s*',source)[0]!=re.match(r'^\s*',target)[0] or re.search(r'\s*$',source)[0]!=re.search(r'\s*$',target)[0]:
        raise ValueError('boundary whitespace differs: '+repr(source))
    if any(ord(c)<32 and c not in '\n\t' for c in target): raise ValueError('control character in translation')
    for token in re.findall(r'https?://[^\s]+|/qt\w*\b|\|[cCrR]|\|[HTAtah]',source):
        if token not in target: raise ValueError('missing command/markup: '+source)
# Explicit source audit: anything new that looks like prose must be localized
# or given a reviewed exemption; native identifiers and diagnostics stay stable.
TOKENS = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.S)
def untranslated_literals(root):
    result={}
    for p in root.glob('*.lua'):
        if p.name in ('Tests.lua','Localization.lua','Locales.lua','LocalizedReleaseNotes.lua','ReleaseNotes.lua','Diagnostics.lua'):continue
        text=p.read_text()
        for m in TOKENS.finditer(text):
            raw=m[0]
            if raw[0] not in ('"', "'") or text[max(0,m.start()-2):m.start()]=='L(':continue
            value=ast.literal_eval(raw)
            if not re.search('[A-Za-z]{3}',value):continue
            if not (' ' in value or re.fullmatch('[A-Z][a-z]+[!:?…]?',value)):continue
            if re.search(r'Interface\\|Fonts\\|^https?://',value):continue
            result.setdefault(p.name,[])
            if value not in result[p.name]:result[p.name].append(value)
    return {k:sorted(v) for k,v in sorted(result.items())}

def check(root,write=False):
    root=Path(root); sources=source_strings(root);
    audited=read(root/'locales/source_audit.json')
    if untranslated_literals(root)!=audited['exemptions']:raise ValueError('Unreviewed prose or stale exemption in locales/source_audit.json')
    outputs={root/'locales/enUS.json':dumps({s:s for s in sources})}
    tables={}
    for locale in LOCALES:
        table=read(root/'locales'/f'{locale}.json')
        if set(table)!=set(sources): raise ValueError(locale+' missing/extra source keys: '+str(set(sources)^set(table)))
        for source,target in table.items():validate_translation(source,target)
        tables[locale]=table
    outputs[root/'Locales.lua']='-- Generated by scripts/localization.py; edit locales/*.json.\nlocal _, namespace = ...\nnamespace.localizations = '+lua(tables)+'\n'
    toc=root/'QuestTogether.toc'
    metadata=toc.read_text()
    description='Quest progress chat bubbles and logs for party and nearby players.'
    metadata=re.sub(r'^## Notes-(?:deDE|frFR|esES|esMX|ptBR|ruRU|itIT|koKR|zhCN|zhTW):.*\n','',metadata,flags=re.M)
    additions=''.join('## Notes-'+locale+': '+tables[locale][description]+'\n' for locale in LOCALES)
    metadata=re.sub(r'(^## Notes:.*\n)',lambda m:m[0]+additions,metadata,count=1,flags=re.M)
    outputs[toc]=metadata
    for path,text in outputs.items():
        if write:path.write_text(text)
        elif not path.exists() or path.read_text()!=text:raise ValueError('stale generated localization: '+str(path))
    return len(sources)
def release_note_outputs(root,notes,previous_version=None):
    from check_release_notes import parse_notes
    root=Path(root); outputs={}; tables={}; expected=digest(notes)
    for locale in LOCALES:
        path=root/'release_notes'/f'{locale}.json'; wrapper=read(path)
        if not isinstance(wrapper,dict) or set(wrapper)!={'source_sha256','notes'} or wrapper['source_sha256']!=expected:raise ValueError(locale+' release translation is stale')
        translated=parse_notes(json.dumps(wrapper['notes'],ensure_ascii=False))
        if translated['version']!=(previous_version or notes['version']):raise ValueError(locale+' translated version mismatch')
        if len(translated['sections'])!=len(notes['sections']):raise ValueError(locale+' translated section count mismatch')
        for a,b in zip(notes['sections'],translated['sections']):
            if len(a['items'])!=len(b['items']) or a.get('illustration')!=b.get('illustration'):raise ValueError(locale+' translated section structure mismatch')
        translated['version']=notes['version'];tables[locale]=translated
        outputs[path]=dumps({'source_sha256':expected,'notes':translated})
    outputs[root/'LocalizedReleaseNotes.lua']='-- Generated localized release notes.\nlocal _, namespace = ...\nnamespace.releaseNotesByLocale = '+lua(tables)+'\n'
    return outputs
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--write',action='store_true');a=p.parse_args()
    print(str(check(a.root,a.write))+' source strings verified in all '+str(len(LOCALES))+' translated locales')
