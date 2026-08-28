"""onlyoneshot.ovdrjm(UTF-16 JSON)에서 월드 트리 요약을 뽑아 docs/world-tree.md로 쓴다.
사용: python docs/dump_world_tree.py <path-to-.ovdrjm>"""
import json, sys, pathlib, collections

def kids(n): return n.get("LuaChildren") or []
def count(n): return 1 + sum(count(c) for c in kids(n))
def types(n, acc):
    for c in kids(n):
        acc[c.get("InstanceType")] += 1; types(c, acc)
    return acc

src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "onlyoneshot.ovdrjm")
root = json.loads(src.read_text(encoding="utf-16"))["Root"]
out = ["# 월드 트리 (onlyoneshot.ovdrjm 요약)", "",
       "Studio 프로젝트 파일은 개당 29 MB의 UTF-16 JSON이라 리포에 넣지 않는다.",
       "대신 이 문서가 월드 구성을 기록한다. `docs/dump_world_tree.py`로 재생성한다.", ""]
for svc in kids(root):
    if not kids(svc): continue
    out.append(f"## {svc.get('Name')} — 총 {count(svc)-1} 인스턴스\n")
    out += ["| 이름 | 타입 | 하위 | 구성 |", "|---|---|---:|---|"]
    for c in kids(svc):
        top = ", ".join(f"{k} {v}" for k, v in types(c, collections.Counter()).most_common(3))
        out.append(f"| {c.get('Name')} | {c.get('InstanceType')} | {count(c)-1} | {top} |")
    out.append("")
pathlib.Path("docs/world-tree.md").write_text("\n".join(out), encoding="utf-8")
