# Helpers de edição do PRD: substituem o ITEM INTEIRO (C9).

def load(): return open('PRD.md').read()
def save(s): open('PRD.md','w').write(s)
def item_end(s, start):
    ends=[]
    for mark in ["\n- **", "\n  - **", "\n### ", "\n## ", "\n\n", "\n| "]:
        k=s.find(mark, start+1)
        if k!=-1: ends.append(k)
    return min(ends)
def item_replace(s, prefix, new):
    i=s.index(prefix); j=item_end(s, i)
    return s[:i]+new+s[j:]
def row_replace(s, prefix, new):
    i=s.index(prefix); j=s.index("\n", i)
    return s[:i]+new+s[j:]
def rep(s,a,b):
    assert a in s, ('MISSING', a[:90]); return s.replace(a,b,1)
