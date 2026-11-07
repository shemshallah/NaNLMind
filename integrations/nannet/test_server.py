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
 def issue(self,endpoint="nan://GM0:SC0:MC0:BS0:HW0",scopes=None):
  s,d=self.req("POST","/admin/tokens",{"address":endpoint,"scopes":scopes or ["intake","dataset"],"ttl_seconds":3600}, "a"*48);self.assertEqual(s,201);return d["token"]

 def device_report(self):
  return {"platform":"Android","os_version":"13","app_version":"0.1.0","abi":"arm64-v8a","cpu_cores":8,"ram_mb":4096,"storage_free_mb":1024,"capabilities":["n16t","corpus-upload"]}
 def register_device(self,secret):
  payload={"device_secret":secret,"consent":True,"terms_version":"nannet-device-registration-v1","system_report":self.device_report()}
  return self.req("POST","/v1/devices/register",payload)
 def test_device_registration_allocates_exclusive_first_available_slots_and_resumes(self):
  secret="A"*43
  status,first=self.register_device(secret)
  self.assertEqual(status,201);self.assertEqual(first["address"],"nan://GM0:SC0:MC0:BS0:HW8")
  self.assertEqual(first["node_point"],9);self.assertEqual(first["head_count"],256)
  status,again=self.register_device(secret)
  self.assertEqual(status,201);self.assertEqual(again["device_id"],first["device_id"])
  self.assertEqual(again["address"],first["address"]);self.assertNotEqual(again["token"],first["token"])
  self.assertEqual(self.req("GET","/v1/devices/me",token=first["token"])[0],401)
  status,second=self.register_device("B"*43)
  self.assertEqual(status,201);self.assertEqual(second["address"],"nan://GM0:SC0:MC0:BS0:HW9")
  self.assertNotEqual(first["device_id"],second["device_id"])
 def test_device_release_waits_for_pending_work_then_revokes_and_frees_slot(self):
  status,device=self.register_device("C"*43);self.assertEqual(status,201)
  db=server.connect()
  try:db.execute("INSERT INTO observations(event_id,endpoint_id,received_at,payload_json) VALUES(?,?,?,?)",("d"*64,device["address"],server.now(),"{}"));db.commit()
  finally:db.close()
  status,blocked=self.req("POST","/v1/devices/release",{},device["token"])
  self.assertEqual(status,409);self.assertIn("pending_work",blocked["error"])
  db=server.connect()
  try:db.execute("UPDATE observations SET status='folded' WHERE event_id=?",("d"*64,));db.commit()
  finally:db.close()
  status,released=self.req("POST","/v1/devices/release",{},device["token"])
  self.assertEqual(status,200);self.assertTrue(released["token_revoked"])
  self.assertEqual(self.req("GET","/v1/address",token=device["token"])[0],401)
  status,next_device=self.register_device("D"*43)
  self.assertEqual(status,201);self.assertEqual(next_device["address"],device["address"])
 def test_device_system_report_and_error_reporting(self):
  status,device=self.register_device("E"*43);self.assertEqual(status,201)
  status,me=self.req("GET","/v1/devices/me",token=device["token"])
  self.assertEqual(status,200);self.assertEqual(me["system_report"]["abi"],"arm64-v8a")
  status,report=self.req("POST","/v1/devices/report",{"report_type":"system_error","summary":"Thermal throttling detected","details":"CPU frequency drops during long training job","system_report":self.device_report()},device["token"])
  self.assertEqual(status,202);self.assertEqual(report["state"],"received")
  status,admin=self.req("GET","/admin/device/reports",token="a"*48)
  self.assertEqual(status,200);self.assertEqual(admin["reports"][0]["report_id"],report["report_id"])
 def test_device_registration_requires_consent_and_nonidentifying_report(self):
  payload={"device_secret":"F"*43,"consent":False,"terms_version":"nannet-device-registration-v1","system_report":self.device_report()}
  self.assertEqual(self.req("POST","/v1/devices/register",payload)[0],400)
  payload["consent"]=True;payload["system_report"]["mac_address"]="aa:bb:cc:dd:ee:ff"
  self.assertEqual(self.req("POST","/v1/devices/register",payload)[0],400)
 def test_dynamic_node_slots_cannot_be_admin_token_bypassed(self):
  self.assertEqual(self.req("POST","/admin/tokens",{"address":"nan://GM0:SC0:MC0:BS0:HW4","scopes":["intake"]},token="a"*48)[0],400)
  token=self.issue("nan://GM0:SC0:MC0:BS0:HW1",["intake"])
  self.assertEqual(self.req("GET","/v1/address",token=token)[0],200)

 def test_nan_address_identity_and_slot_translation(self):
  t=self.issue("nan://GM0:SC0:MC0:BS0:HW3",["intake"])
  status,identity=self.req("GET","/v1/address",token=t,headers={"X-NaN-Address":"nan://GM0:SC0:MC0:BS0:HW3"})
  self.assertEqual(status,200);self.assertEqual(identity["node_point"],4);self.assertEqual(identity["coordinates"],{"gm":0,"sc":0,"mc":0,"bs":0,"hw":3})
  self.assertEqual(self.req("GET","/v1/address",token=t,headers={"X-NaN-Address":"nan://GM0:SC0:MC0:BS0:HW2"})[0],401)
  self.assertEqual(server.address_node_point("nan://GM255:SC255:MC255:BS255:HW255"),256)
 def test_portal_served_without_credentials(self):
  status,body=self.req("GET","/")
  self.assertEqual(status,200);self.assertIn(b"NANNET",body);self.assertIn(b"connectEndpoint",body);self.assertIn(b"loadQuarantine",body);self.assertIn(b"reviewDataset",body)
  status,body=self.req("GET","/portal")
  self.assertEqual(status,200);self.assertIn(b"nan://GM0",body)

 def test_admin_training_status_is_read_only(self):
  status,body=self.req("GET","/admin/training/status",token="a"*48)
  self.assertEqual(status,200);self.assertEqual(body["node_count"],0);self.assertEqual(body["corpus_receipts"],0)
  self.assertEqual(self.req("GET","/admin/training/status",token="r"*48)[0],401)

 def test_admin_keeper_and_model_status_routes(self):
  status,keeper=self.req("GET","/admin/keeper/status",token="a"*48)
  self.assertEqual(status,200);self.assertEqual(keeper["status"],"disabled")
  status,models=self.req("GET","/admin/models/status",token="a"*48)
  self.assertEqual(status,200);self.assertEqual(models["keeper_action"],"not_started")
  self.assertEqual(self.req("GET","/admin/keeper/status",token="p"*48)[0],401)
 def test_256_and_route_scoping(self):
  s,d=self.req("GET","/healthz");self.assertEqual(s,200);self.assertEqual(d["bootstrap_endpoints"],256);self.assertEqual(len(server.ENDPOINTS),256);self.assertIn("nan://GM0:SC0:MC0:BS0:HW0",server.ENDPOINTS);self.assertTrue(server.valid_nan_address("nan://GM255:SC255:MC255:BS255:HW255"));self.assertFalse(server.valid_nan_address("nan://GM256:SC0:MC0:BS0:HW0"))
  t=self.issue("nan://GM0:SC0:MC0:BS0:HW1",["intake"]);s,r=self.req("GET","/v1/routes",token=t);self.assertEqual(s,200);self.assertIn("n16t.peer",r["routes"]);self.assertNotIn("deeprepo.keeper",r["routes"])
  self.assertEqual(self.req("POST","/admin/tokens",{"address":"nan://GM0:SC0:MC0:BS0:HW1","scopes":["runner"]},token="a"*48)[0],400)
 def test_android_route_diff_intake_is_address_bound_and_unverified(self):
  token=self.issue("nan://GM0:SC0:MC0:BS0:HW1",["intake"])
  diff={"universe":0,"node":2,"layer":0,"control_point":1,"base_generation":0,"epoch":123,"entries":[]}
  diff["digest"]=hashlib.sha256(server.jbytes(diff)).hexdigest()
  status,body=self.req("POST","/v1/intake/route",diff,token)
  self.assertEqual(status,202);self.assertFalse(body["outcome_verified"])
  status,replay=self.req("POST","/v1/intake/route",diff,token)
  self.assertEqual(status,200);self.assertEqual(replay["state"],"duplicate_noop")
  tampered=dict(diff,epoch=124)
  self.assertEqual(self.req("POST","/v1/intake/route",tampered,token)[0],400)
  wrong_node=dict(diff,node=3)
  wrong_node["digest"]=hashlib.sha256(server.jbytes({k:v for k,v in wrong_node.items() if k!="digest"})).hexdigest()
  self.assertEqual(self.req("POST","/v1/intake/route",wrong_node,token)[0],400)

 def test_observation_unverified_and_idempotent(self):
  t=self.issue("nan://GM0:SC0:MC0:BS0:HW1",["intake","observation"]);e={"protocol":"nanlm.endpoint-observation","version":1,"event_id":"b"*64,"base_generation":4,"active_heads":[1,1,255],"outcome_verified":False}
  s,a=self.req("POST","/v1/observations",e,t);self.assertEqual(s,202);self.assertEqual(a["endpoint_id"],"nan://GM0:SC0:MC0:BS0:HW1");self.assertFalse(a["outcome_verified"])
  s,b=self.req("POST","/v1/observations",e,t);self.assertEqual(s,200);self.assertEqual(b["state"],"duplicate_noop")
  self.assertEqual(self.req("POST","/v1/observations",dict(e,event_id="c"*64,correct=True),t)[0],400)
 def test_dataset_quarantine_external_validation(self):
  t=self.issue("nan://GM0:SC0:MC0:BS0:HW2");raw=[b"abc",b"defg"];full=b"".join(raw)
  self.assertEqual(self.req("POST","/v1/datasets/demo-1/begin",{"chunk_count":2,"metadata":{"protocol":"nanlm.dataset","version":1,"content_type":"text/plain","encoding":"utf-8","license":"CC0-1.0","provenance":"synthetic unit-test corpus","split":"train"}},t)[0],201)
  for i,b in enumerate(raw):
   self.assertEqual(self.req("PUT",f"/v1/datasets/demo-1/chunks/{i}",b,t,{"Content-Type":"application/octet-stream","X-Chunk-SHA256":hashlib.sha256(b).hexdigest()})[0],201)
  s,d=self.req("POST","/v1/datasets/demo-1/seal",{"total_bytes":len(full),"sha256":hashlib.sha256(full).hexdigest()},t);self.assertEqual(s,202);self.assertEqual(d["state"],"quarantine_pending_external_validation")
  s,q=self.req("GET","/internal/datasets",token="v"*48);self.assertEqual(s,200);self.assertEqual(q["datasets"][0]["dataset_id"],"demo-1")
  s,b=self.req("GET","/internal/datasets/demo-1/chunks/0",token="v"*48);self.assertEqual(s,200);self.assertEqual(b,raw[0])
  self.assertEqual(self.req("GET","/internal/datasets/validated",token="r"*48)[0],200)
  s,a=self.req("PATCH","/internal/datasets/demo-1/validation",{"passed":True,"report":{"utf8":"pass"}}, "v"*48);self.assertEqual(s,200);self.assertTrue(a["training_eligible"])
  s,approved=self.req("GET","/internal/datasets/validated",token="r"*48);self.assertEqual(s,200);self.assertEqual(approved["datasets"][0]["dataset_id"],"demo-1")
  s,runner_blob=self.req("GET","/internal/datasets/demo-1/chunks/0",token="r"*48);self.assertEqual(s,200);self.assertEqual(runner_blob,raw[0])
  receipt={"generation":7,"dataset_sha256":hashlib.sha256(full).hexdigest()}
  s,committed=self.req("POST","/internal/datasets/demo-1/commit",receipt,token="r"*48);self.assertEqual(s,200);self.assertEqual(committed["state"],"committed");self.assertTrue(committed["staging_bytes_released"])
  self.assertEqual(self.req("GET","/internal/datasets/demo-1/chunks/0",token="r"*48)[0],410)
  s,again=self.req("POST","/internal/datasets/demo-1/commit",receipt,token="r"*48);self.assertEqual(s,200);self.assertTrue(again["duplicate_noop"])
  s,audit=self.req("GET","/internal/datasets/committed",token="r"*48);self.assertEqual(s,200);self.assertEqual(audit["datasets"][0]["committed_generation"],7)
 def test_bad_chunk_digest(self):
  t=self.issue();self.req("POST","/v1/datasets/bad/begin",{"chunk_count":1,"metadata":{"protocol":"nanlm.dataset","version":1,"content_type":"text/plain","encoding":"utf-8","license":"CC0-1.0","provenance":"synthetic unit-test corpus","split":"train"}},t)
  s,_=self.req("PUT","/v1/datasets/bad/chunks/0",b"abc",t,{"Content-Type":"application/octet-stream","X-Chunk-SHA256":"0"*64});self.assertEqual(s,400)

 def test_training_state_and_durable_receipt_lookup(self):
  status,state=self.req("GET","/v1/training/state/1",token="m"*48)
  self.assertEqual(status,200);self.assertEqual(state["generation"],0)
  payload={"source_endpoint":"bootstrap","node":1,"base_generation":0,"nanclock_tick":1,"updates":[{"head":3,"layer":0,"epoch":1,"vector":[1]*16,"strength_delta":4}]}
  key=hashlib.sha256(b"dataset-a\\0"+b"f"*64).hexdigest()
  status,merged=self.req("POST","/v1/training/merge",payload,token="m"*48,headers={"Idempotency-Key":key})
  self.assertEqual(status,200);self.assertEqual(merged["generation"],1)
  status,receipt=self.req("GET","/v1/training/receipts/"+key,token="m"*48)
  self.assertEqual(status,200);self.assertEqual(receipt,merged)
  status,state=self.req("GET","/v1/training/state/1",token="m"*48)
  self.assertEqual(status,200);self.assertEqual(state["generation"],1)

 def test_corpus_receipts_survive_generic_replay_pruning(self):
  store=server.get_merge_store()
  for i in range(4096):
   store.state["idempotency"]["generic-"+str(i)]={"body":"x","response":{"generation":1}}
  payload={"source_endpoint":"bootstrap","node":1,"base_generation":0,"nanclock_tick":1,"dataset_id":"durable-corpus","dataset_sha256":"f"*64,"updates":[{"head":4,"layer":0,"epoch":1,"vector":[1]*16,"strength_delta":1}]}
  key=hashlib.sha256(b"durable-corpus\\0"+b"f"*64).hexdigest()
  status,merged=store.merge(payload,key,"bootstrap")
  self.assertEqual(status,200);self.assertEqual(merged["generation"],1)
  self.assertIsNotNone(store.receipt(key))
  status,replay=store.merge(payload,key,"bootstrap")
  self.assertEqual(status,200);self.assertEqual(replay,merged)
  self.assertEqual(store.snapshot(1)["generation"],1)

 def test_training_merge_is_runner_only_and_idempotent(self):
  payload={"source_endpoint":"bootstrap","node":1,"base_generation":0,"nanclock_tick":7,"updates":[{"head":9,"strength_delta":2}]}
  status,body=self.req("POST","/v1/training/merge",payload,token="m"*48,headers={"Idempotency-Key":"runner-commit-1"})
  self.assertEqual(status,200);self.assertEqual(body["generation"],1);self.assertEqual(body["source_endpoint"],"bootstrap")
  status,replay=self.req("POST","/v1/training/merge",payload,token="m"*48,headers={"Idempotency-Key":"runner-commit-1"})
  self.assertEqual(status,200);self.assertEqual(replay,body)
  self.assertEqual(self.req("POST","/v1/training/merge",payload,token="p"*48,headers={"Idempotency-Key":"runner-commit-2"})[0],401)
  self.assertEqual(self.req("POST","/v1/training/merge",dict(payload,source_endpoint="my_android"),token="m"*48,headers={"Idempotency-Key":"runner-commit-3"})[0],403)
 def test_n16t_is_scoped_and_fails_closed_without_peer(self):
  t=self.issue("nan://GM0:SC0:MC0:BS0:HW1",["n16t"])
  frame=b"x"*36
  status,body=self.req("POST","/n16t",frame,t,{"Content-Type":"application/vnd.nan16.n16t"})
  self.assertEqual(status,503)
  self.assertEqual(body["error"],"n16t_peer_not_configured")
  self.assertEqual(self.req("POST","/n16t",frame,t,{"Content-Type":"application/x-n16t"})[0],503)
  self.assertEqual(self.req("POST","/n16t",frame,t,{"Content-Type":"application/octet-stream"})[0],415)

if __name__=="__main__":unittest.main()
