import numpy as np, glob, sys, time, json
M='/home/claude/NaN16_Palindromic_Temporal_Computer_MERGED/'
def corpus(name):
    if name=='A': fs=sorted(glob.glob(M+'docs/*.md'))+[M+'BRAINSTORM_4.md']
    else: fs=[M+'src/topology.cpp',M+'include/nan16_ptc.hpp']
    return np.frombuffer(b''.join(open(f,'rb').read() for f in fs),dtype=np.uint8).astype(np.int64)
N=256
def make(variant,seed):
    r=np.random.default_rng(seed)
    P=(r.normal(size=(N,N))*0.9/np.sqrt(N)).astype(np.float32)
    if variant=='sym': P*=np.sqrt(2)
    return dict(P=P,U=(r.normal(size=(N,256))*0.1).astype(np.float32),b=np.zeros(N,np.float32),
                V=(r.normal(size=(256,N))*0.1).astype(np.float32),c=np.zeros(256,np.float32))
def getW(p,variant):
    P=p['P']
    return P if variant=='full' else ((P+P.T)/2 if variant=='sym' else (P-P.T)/2)
def fwd(p,variant,X,h0):
    W=getW(p,variant); B,T=X.shape; hs=[];h=h0
    for t in range(T):
        h=np.tanh(h@W.T+p['U'][:,X[:,t]].T+p['b']); hs.append(h)
    H=np.stack(hs,1)  # B,T,N
    L=H@p['V'].T+p['c']
    return H,L
def loss_grad(p,variant,X,Y,h0):
    B,T=X.shape; W=getW(p,variant)
    H,L=fwd(p,variant,X,h0)
    L=L-L.max(2,keepdims=True); Pr=np.exp(L); Pr/=Pr.sum(2,keepdims=True)
    nll=-np.log(Pr[np.arange(B)[:,None],np.arange(T)[None],Y]+1e-12).mean()
    dL=Pr.copy(); dL[np.arange(B)[:,None],np.arange(T)[None],Y]-=1; dL/=(B*T)
    g={k:np.zeros_like(v) for k,v in p.items()}
    g['V']=np.einsum('btk,btn->kn',dL,H); g['c']=dL.sum((0,1))
    dH=dL@p['V']; dW=np.zeros((N,N),np.float32); dh=np.zeros((B,N),np.float32)
    for t in range(T-1,-1,-1):
        dpre=(dH[:,t]+dh)*(1-H[:,t]**2)
        hp=H[:,t-1] if t>0 else h0
        dW+=dpre.T@hp; g['b']+=dpre.sum(0)
        np.add.at(g['U'].T,X[:,t],dpre)
        dh=dpre@W
    g['P']=dW if variant=='full' else ((dW+dW.T)/2 if variant=='sym' else (dW-dW.T)/2)
    return nll,g,H[:,-1]
def evaluate(p,variant,te,streams=16):
    n=(len(te)-1)//streams; X=te[:n*streams].reshape(streams,n); Y=te[1:n*streams+1].reshape(streams,n)
    h=np.zeros((streams,N),np.float32); tot=0
    for s in range(0,n,64):
        H,L=fwd(p,variant,X[:,s:s+64],h); h=H[:,-1]
        L=L-L.max(2,keepdims=True); lp=L-np.log(np.exp(L).sum(2,keepdims=True))
        yy=Y[:,s:s+64]; tot+=-lp[np.arange(streams)[:,None],np.arange(yy.shape[1])[None],yy].sum()
    return tot/(streams*n)/np.log(2)
def run(cname,variant,iters,seed=0,B=16,T=32,lr=3e-3,evals=(25,50,100,200,400,800,1600,3200)):
    d=corpus(cname); sp=int(len(d)*.8); tr,te=d[:sp],d[sp:]
    p=make(variant,seed); m={k:np.zeros_like(v) for k,v in p.items()}; v2={k:np.zeros_like(x) for k,x in p.items()}
    r=np.random.default_rng(seed+1); out=[]; t0=time.time(); best=99
    for it in range(1,iters+1):
        st=r.integers(0,len(tr)-T-1,B); X=np.stack([tr[s:s+T] for s in st]); Y=np.stack([tr[s+1:s+T+1] for s in st])
        nll,g,_=loss_grad(p,variant,X,Y,np.zeros((B,N),np.float32))
        gn=np.sqrt(sum((x**2).sum() for x in g.values()))
        sc=min(1,1.0/(gn+1e-9))
        for k in p:
            gk=g[k]*sc; m[k]=.9*m[k]+.1*gk; v2[k]=.999*v2[k]+.001*gk**2
            p[k]-=lr*(m[k]/(1-.9**it))/(np.sqrt(v2[k]/(1-.999**it))+1e-8)
        if it in evals or it==iters:
            e=evaluate(p,variant,te); best=min(best,e)
            out.append((it,it*B*T,round(float(nll/np.log(2)),3),round(float(e),3)))
            print(cname,variant,'iter',it,'bytes_seen',it*B*T,'train',out[-1][2],'heldout',out[-1][3],f'{time.time()-t0:.0f}s',flush=True)
    return out,p
if __name__=='__main__':
    cname,variant,iters=sys.argv[1],sys.argv[2],int(sys.argv[3])
    out,p=run(cname,variant,iters)
    json.dump(out,open(f'res_{cname}_{variant}.json','w'))
    np.savez(f'w_{cname}_{variant}.npz',**p)
