#!/usr/bin/env python3
import argparse, pathlib
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--keyed",action="store_true")
    parser.add_argument("expected")
    parser.add_argument("actual")
    args=parser.parse_args()
    a=pathlib.Path(args.expected).read_text().splitlines(); b=pathlib.Path(args.actual).read_text().splitlines()
    if args.keyed:
        def key(line):
            fields=line.split()
            if len(fields)<4 or fields[0]!="C":
                raise SystemExit(f"invalid keyed trace line: {line}")
            return int(fields[1]),int(fields[2]),int(fields[3])
        if len({key(line) for line in a})!=len(a) or len({key(line) for line in b})!=len(b):
            raise SystemExit("duplicate epoch/warp/sequence key in architectural trace")
        a=sorted(a,key=key); b=sorted(b,key=key)
    for i,(x,y) in enumerate(zip(a,b),1):
        if x!=y: raise SystemExit(f"first architectural mismatch at trace line {i}\nexpected: {x}\nactual:   {y}")
    if len(a)!=len(b): raise SystemExit(f"trace length mismatch expected={len(a)} actual={len(b)}")
    events=len(a) if args.keyed else len(a)//3
    print(f"PASS architectural trace comparison events={events}")
if __name__=="__main__": main()
