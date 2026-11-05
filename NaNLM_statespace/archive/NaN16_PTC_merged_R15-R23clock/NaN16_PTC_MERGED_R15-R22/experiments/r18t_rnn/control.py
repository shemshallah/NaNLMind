import sys, json, time, numpy as np
import rnn
cfgs=[('full',256),('sym',256),('anti',256),('full',213),('full',181)]
seeds=[0,1,2]
corp={'B':3200,'A':1600}
done=set()
try:
    for l in open('control_results.jsonl'): d=json.loads(l); done.add((d['corpus'],d['variant'],d['hidden'],d['seed']))
except FileNotFoundError: pass
for c,iters in corp.items():
    for seed in seeds:
        for v,h in cfgs:
            if (c,v,h,seed) in done: continue
            rnn.N=h; t0=time.time()
            out,p=rnn.run(c,v,iters,seed=seed,evals=(100,200,400,800,1600,3200))
            nparams=sum(x.size for x in p.values()) - (p['P'].size//2 if v!='full' else 0)
            open('control_results.jsonl','a').write(json.dumps(dict(corpus=c,variant=v,hidden=h,seed=seed,curve=out,eff_params=int(nparams),secs=round(time.time()-t0)))+'\n')
