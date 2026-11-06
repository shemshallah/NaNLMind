import hashlib, http.client, json, os, tempfile, threading, unittest
from http.server import ThreadingHTTPServer
from unittest.mock import patch
import server

class NannetTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory()
  self.env=patch.dict(os.environ,{"NANLM_DATA_DIR":self.tmp.name,"NANLM_TOKEN_PEPPER":"p"*48,"NANLM_ADMIN_TOKEN":"a"*48,"NANLM_VALIDATOR_TOKEN":"v"*48,"NANLM_RUNNER_TOKEN":"r"*48,"NANLM_BOOTSTRAP_TOKEN":"m"*48,"NANLM_MERGE_ROOT":self.tmp.name+"/merge"})
  self.env.start(); server.MERGE_STORE=None; server.ROOT=server.Path(self.tmp.name);server.BLOBS=server.ROOT/"blobs";server.DB_PATH=server.ROOT/"test.sqlite3";server.DATASET_QUOTA=1024*1024;server.CHUNK_BYTES=65536
  self.httpd=server.BoundedHTTPServer(("127.0.0.1",0),server.Handler);self.thread=threading.Thread(target=self.httpd.serve_forever,daemon=True);self.thread.start();self.port=self.httpd.server_address[1]
 def tearDown(self):
  self.httpd.shutdown();self.httpd.server_close();self.thread.join(2);self.env.stop();self.tmp.cleanup()
 def req(self,method,path,body=None,token=None,headers=None):
  c=http.client.HTTPConnection("127.0.0.1",self.port,timeout=5);h=dict(headers or {});payload=body
  if isinstance(body,dict):payload=json.dumps(body).encode();h["Content-Type"]="application/json"
  if token:h["Authorization"]="Bearer "+token
  c.request(method,path,body=payload,headers=h);r=c.getresponse();raw=r.read();c.close()
  try:v=json.loads(raw.decode())
  except Exception:v=raw
  return r.status,v
 def issue(self,endpoint="bootstrap-000",scopes=None):
  s,d=self.req("POST","/admin/tokens",{"endpoint_id":endpoint,"scopes":scopes or ["intake","dataset"],"ttl_seconds":3600}, "a"*48);self.assertEqual(s,201);return d["token"]
 def test_256_and_route_scoping(self):
  s,d=self.req("GET","/healthz");self.assertEqual(s,200);self.assertEqual(d["bootstrap_endpoints"],256);self.assertIn("bootstrap-255",server.ENDPOINTS)
  t=self.issue("my_android",["intake"]);s,r=self.req("GET","/v1/routes",token=t);self.assertEqual(s,200);self.assertIn("n16t.peer",r["routes"]);self.assertNotIn("deeprepo.keeper",r["routes"])
  self.assertEqual(self.req("POST","/admin/tokens",{"endpoint_id":"bootstrap-000","scopes":["runner"]},token="a"*48)[0],400)
 def test_observation_unverified_and_idempotent(self):
  t=self.issue("bootstrap-007",["intake","observation"]);e={"protocol":"nanlm.endpoint-observation","version":1,"event_id":"b"*64,"base_generation":4,"active_heads":[1,1,255],"outcome_verified":False}
  s,a=self.req("POST","/v1/observations",e,t);self.assertEqual(s,202);self.assertEqual(a["endpoint_id"],"bootstrap-007");self.assertFalse(a["outcome_verified"])
  s,b=self.req("POST","/v1/observations",e,t);self.assertEqual(s,200);self.assertEqual(b["state"],"duplicate_noop")
  self.assertEqual(self.req("POST","/v1/observations",dict(e,event_id="c"*64,correct=True),t)[0],400)
 def test_dataset_quarantine_external_validation(self):
  t=self.issue("hermes_demo");raw=[b"abc",b"defg"];full=b"".join(raw)
  self.assertEqual(self.req("POST","/v1/datasets/demo-1/begin",{"chunk_count":2},t)[0],201)
  for i,b in enumerate(raw):
   self.assertEqual(self.req("PUT",f"/v1/datasets/demo-1/chunks/{i}",b,t,{"Content-Type":"application/octet-stream","X-Chunk-SHA256":hashlib.sha256(b).hexdigest()})[0],201)
  s,d=self.req("POST","/v1/datasets/demo-1/seal",{"total_bytes":len(full),"sha256":hashlib.sha256(full).hexdigest()},t);self.assertEqual(s,202);self.assertEqual(d["state"],"quarantine_pending_external_validation")
  s,q=self.req("GET","/internal/datasets",token="v"*48);self.assertEqual(s,200);self.assertEqual(q["datasets"][0]["dataset_id"],"demo-1")
  s,b=self.req("GET","/internal/datasets/demo-1/chunks/0",token="v"*48);self.assertEqual(s,200);self.assertEqual(b,raw[0])
  self.assertEqual(self.req("GET","/internal/datasets/validated",token="r"*48)[0],200)
  s,a=self.req("PATCH","/internal/datasets/demo-1/validation",{"passed":True,"report":{"utf8":"pass"}}, "v"*48);self.assertEqual(s,200);self.assertTrue(a["training_eligible"])
  s,approved=self.req("GET","/internal/datasets/validated",token="r"*48);self.assertEqual(s,200);self.assertEqual(approved["datasets"][0]["dataset_id"],"demo-1")
  s,runner_blob=self.req("GET","/internal/datasets/demo-1/chunks/0",token="r"*48);self.assertEqual(s,200);self.assertEqual(runner_blob,raw[0])
  self.assertEqual(self.req("DELETE","/admin/datasets/demo-1",token="a"*48)[0],409)
 def test_bad_chunk_digest(self):
  t=self.issue();self.req("POST","/v1/datasets/bad/begin",{"chunk_count":1},t)
  s,_=self.req("PUT","/v1/datasets/bad/chunks/0",b"abc",t,{"Content-Type":"application/octet-stream","X-Chunk-SHA256":"0"*64});self.assertEqual(s,400)

 def test_training_merge_is_runner_only_and_idempotent(self):
  payload={"source_endpoint":"bootstrap","node":1,"base_generation":0,"nanclock_tick":7,"updates":[{"head":9,"strength_delta":2}]}
  status,body=self.req("POST","/v1/training/merge",payload,token="m"*48,headers={"Idempotency-Key":"runner-commit-1"})
  self.assertEqual(status,200);self.assertEqual(body["generation"],1);self.assertEqual(body["source_endpoint"],"bootstrap")
  status,replay=self.req("POST","/v1/training/merge",payload,token="m"*48,headers={"Idempotency-Key":"runner-commit-1"})
  self.assertEqual(status,200);self.assertEqual(replay,body)
  self.assertEqual(self.req("POST","/v1/training/merge",payload,token="p"*48,headers={"Idempotency-Key":"runner-commit-2"})[0],401)
  self.assertEqual(self.req("POST","/v1/training/merge",dict(payload,source_endpoint="my_android"),token="m"*48,headers={"Idempotency-Key":"runner-commit-3"})[0],403)
 def test_n16t_is_scoped_and_fails_closed_without_peer(self):
  t=self.issue("my_android",["n16t"])
  frame=b"x"*36
  status,body=self.req("POST","/n16t",frame,t,{"Content-Type":"application/vnd.nan16.n16t"})
  self.assertEqual(status,503)
  self.assertEqual(body["error"],"n16t_peer_not_configured")
  self.assertEqual(self.req("POST","/n16t",frame,t,{"Content-Type":"application/octet-stream"})[0],415)

if __name__=="__main__":unittest.main()
