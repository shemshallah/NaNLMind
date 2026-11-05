"""Logical clock: 256 heads, 4-phase V4 oscillator (alternating byte-swap / bit-reverse), drift, dropped hosts.
Modes: free (no coupling), local (plurality of 8 Hamming-1 neighbours), scratch (global community scratch: phase + epoch)."""
import numpy as np, json
rev16=lambda x:int(f'{x:016b}'[::-1],2); sw=lambda x:((x<<8)|(x>>8))&0xFFFF
# phase k == address image after k alternating ops (S,R,S,R): verified for all addresses
for x in range(65536):
    y=x; im=[x]
    for op in (sw,rev16,sw,rev16): y=op(y); im.append(y)
    assert im[4]==x
idx=np.arange(256); NB=np.stack([idx^(1<<b) for b in range(8)],1)
def plur(votes,r):
    c=np.bincount(votes,minlength=4); return r.choice(np.flatnonzero(c==c.max()))
def sim(mode,seed,T=1600,drop=(400,803),frac=0.3,p=0.25,drift=0.03):
    r=np.random.default_rng(seed); N=256
    rate=1+r.normal(0,drift,N); acc=r.random(N); ph=r.integers(0,4,N); ep=np.zeros(N,int)
    dead=np.zeros(N,bool); dropped=r.choice(N,int(frac*N),replace=False)
    S_ph=0; S_ep=0; order=[]; rec=None
    for t in range(T):
        if t==drop[0]: dead[dropped]=True
        if t==drop[1]: dead[dropped]=False; rejoin=t
        al=~dead
        acc[al]+=rate[al]; adv=al&(acc>=1); acc[adv]-=1
        wrap=adv&(ph==3); ep[wrap]+=1; ph[adv]=(ph[adv]+1)%4
        if mode=='scratch':
            newp=plur(ph[al],r)
            if S_ph==3 and newp==0: S_ep+=1
            S_ph=newp
            rd=al&(r.random(N)<p); ph[rd]=S_ph; ep[rd]=S_ep
        elif mode=='local':
            new=ph.copy()
            for i in np.flatnonzero(al): new[i]=plur(np.append(ph[NB[i]],ph[i]),r)
            ph=new
        c=np.bincount(ph[al],minlength=4); order.append(c.max()/al.sum())
        if t>=drop[1] and rec is None and np.bincount(ph,minlength=4).max()/N>=0.95: rec=t-drop[1]
    o=np.array(order)
    return dict(before=o[200:400].mean(),during=o[500:803].mean(),late=o[1300:].mean(),recover=rec,epoch_spread=int(ep.max()-ep.min()))
out={}
for mode in ('free','local','scratch'):
    rs=[sim(mode,s) for s in range(10)]
    rc=[x['recover'] for x in rs if x['recover'] is not None]
    out[mode]=dict(before=round(float(np.mean([x['before'] for x in rs])),3),during_drop=round(float(np.mean([x['during'] for x in rs])),3),late=round(float(np.mean([x['late'] for x in rs])),3),recovered=f'{len(rc)}/10',median_recover_ticks=float(np.median(rc)) if rc else None,epoch_spread_mean=round(float(np.mean([x['epoch_spread'] for x in rs])),1))
    print(mode,out[mode])
json.dump(out,open('clock_sync_results.json','w'),indent=1)
