#!/usr/bin/env python3
"""NANNET universal, disk-backed intake/control plane. Standard library only."""
from __future__ import annotations
import hashlib, hmac, json, os, re, secrets, sqlite3, tempfile, threading, time, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

ROOT=Path(os.environ.get("NANLM_DATA_DIR","/data/nannet"))
BLOBS=ROOT/"blobs"; DB_PATH=ROOT/"nannet.sqlite3"
MAX_JSON=65536
CHUNK_BYTES=int(os.environ.get("NANLM_CHUNK_BYTES",str(8*1024*1024)))
DATASET_QUOTA=int(os.environ.get("NANLM_DATASET_QUOTA_BYTES",str(6*1024**3)))
EVENT_ID=re.compile(r"^[a-f0-9]{64}$"); HEX=EVENT_ID
ID_RE=re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$")
ADDRESS_RE=re.compile(r"^nan://GM(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]):SC(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]):MC(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]):BS(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]):HW(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$")
def valid_nan_address(value): return isinstance(value,str) and ADDRESS_RE.fullmatch(value) is not None
def address_coordinates(value):
 match=ADDRESS_RE.fullmatch(value) if isinstance(value,str) else None
 if not match: raise ValueError("invalid_nan_address")
 return dict(zip(("gm","sc","mc","bs","hw"),map(int,match.groups())))
def address_node_point(value): return address_coordinates(value)["hw"]+1
def nan_address(gm,sc,mc,bs,hw): return f"nan://GM{gm}:SC{sc}:MC{mc}:BS{bs}:HW{hw}"
NANLM_ADDRESS=nan_address(0,0,0,0,0)
ANDROID_ADDRESS=nan_address(0,0,0,0,1)
HERMES_ADDRESS=nan_address(0,0,0,0,2)
CLOCKED_ADDRESS=nan_address(0,0,0,0,3)
ENDPOINTS={nan_address(0,0,0,0,hw) for hw in range(256)}
MERGE_STORE=None
KEEPER_STATE={"enabled":False,"status":"disabled"}
ROUTES={
 "training.merge":{"audience":["runner","admin"],"description":"Generation-safe evidence merge; runner ring owns commits"},
 "training.validate":{"audience":["validator","admin"],"description":"Validate quarantined corpus packages"},
 "corpus.upload":{"audience":["dataset","intake"],"description":"Upload licensed corpus chunks into quarantine"},
 "device.lease":{"audience":["heartbeat","device.report"],"description":"Heartbeat, report diagnostics, and release an exclusive HW slot"},
 "n16t.peer":{"audience":[ANDROID_ADDRESS,HERMES_ADDRESS,CLOCKED_ADDRESS,NANLM_ADDRESS,"n16t"],"description":"NaN16 transport peer and capability exchange"},
 "deeprepo.keeper":{"audience":["admin"],"description":"GET /admin/keeper/status; DeepRepo keeper health and last action"},
 "models.status":{"audience":["admin"],"description":"GET /admin/models/status; read-only Qwen deployment metadata"}}

def now(): return int(time.time())
def connect():
 ROOT.mkdir(parents=True,exist_ok=True); BLOBS.mkdir(parents=True,exist_ok=True)
 db=sqlite3.connect(DB_PATH,timeout=20); db.row_factory=sqlite3.Row
 db.execute("PRAGMA journal_mode=WAL"); db.execute("PRAGMA synchronous=NORMAL"); db.execute("PRAGMA busy_timeout=20000")
 db.executescript("""
 CREATE TABLE IF NOT EXISTS tokens(token_hash TEXT PRIMARY KEY,endpoint_id TEXT NOT NULL,scopes_json TEXT NOT NULL,expires_at INTEGER NOT NULL,max_requests INTEGER NOT NULL,used_requests INTEGER NOT NULL DEFAULT 0,revoked INTEGER NOT NULL DEFAULT 0,created_at INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS devices(device_id TEXT PRIMARY KEY,key_hash TEXT NOT NULL UNIQUE,created_at INTEGER NOT NULL,last_seen INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'registered',report_json TEXT NOT NULL DEFAULT '{}',terms_version TEXT NOT NULL,consent_at INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS device_leases(lease_id TEXT PRIMARY KEY,address TEXT NOT NULL,device_id TEXT NOT NULL,issued_at INTEGER NOT NULL,expires_at INTEGER NOT NULL,released_at INTEGER,status TEXT NOT NULL DEFAULT 'active');
 CREATE UNIQUE INDEX IF NOT EXISTS one_active_lease_per_address ON device_leases(address) WHERE status='active';
 CREATE UNIQUE INDEX IF NOT EXISTS one_active_lease_per_device ON device_leases(device_id) WHERE status='active';
 CREATE TABLE IF NOT EXISTS device_reports(report_id TEXT PRIMARY KEY,device_id TEXT NOT NULL,address TEXT NOT NULL,created_at INTEGER NOT NULL,report_type TEXT NOT NULL,summary TEXT NOT NULL,details TEXT NOT NULL,system_json TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'open');
 CREATE TABLE IF NOT EXISTS observations(event_id TEXT PRIMARY KEY,endpoint_id TEXT NOT NULL,received_at INTEGER NOT NULL,payload_json TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'pending');
 CREATE TABLE IF NOT EXISTS datasets(dataset_id TEXT PRIMARY KEY,endpoint_id TEXT NOT NULL,created_at INTEGER NOT NULL,expected_chunks INTEGER NOT NULL,total_bytes INTEGER NOT NULL DEFAULT 0,dataset_sha256 TEXT,status TEXT NOT NULL DEFAULT 'uploading',validation_json TEXT,last_error TEXT,metadata_json TEXT NOT NULL DEFAULT '{}',committed_generation INTEGER NOT NULL DEFAULT 0);
 CREATE TABLE IF NOT EXISTS chunks(dataset_id TEXT NOT NULL,chunk_index INTEGER NOT NULL,sha256 TEXT NOT NULL,size_bytes INTEGER NOT NULL,blob_path TEXT NOT NULL,status TEXT NOT NULL,PRIMARY KEY(dataset_id,chunk_index));
 """)
 token_columns={r[1] for r in db.execute("PRAGMA table_info(tokens)").fetchall()}
 if "owner_device_id" not in token_columns:db.execute("ALTER TABLE tokens ADD COLUMN owner_device_id TEXT")
 columns={r[1] for r in db.execute("PRAGMA table_info(datasets)").fetchall()}
 if "metadata_json" not in columns:db.execute("ALTER TABLE datasets ADD COLUMN metadata_json TEXT NOT NULL DEFAULT '{}'")
 if "committed_generation" not in columns:db.execute("ALTER TABLE datasets ADD COLUMN committed_generation INTEGER NOT NULL DEFAULT 0")
 db.commit(); return db

def token_hash(token):
 pepper=os.environ.get("NANLM_TOKEN_PEPPER","")
 if len(pepper)<32: raise RuntimeError("token pepper missing")
 return hmac.new(pepper.encode(),token.encode(),hashlib.sha256).hexdigest()
def jbytes(v): return json.dumps(v,sort_keys=True,separators=(",",":")).encode()

class BoundedHTTPServer(ThreadingHTTPServer):
 daemon_threads=True
 request_queue_size=32
 def __init__(self,server_address,handler):
  self.slots=threading.BoundedSemaphore(max(2,min(32,int(os.environ.get("NANLM_HTTP_WORKERS","8")))))
  super().__init__(server_address,handler)
 def process_request(self,request,client_address):
  self.slots.acquire()
  try:super().process_request(request,client_address)
  except Exception:
   self.slots.release()
   raise
 def process_request_thread(self,request,client_address):
  try:super().process_request_thread(request,client_address)
  finally:self.slots.release()

class Handler(BaseHTTPRequestHandler):
 server_version="NANNET/1"
 def log_message(self,fmt,*args): print("nannet "+(fmt%args),flush=True)
 def reply(self,code,obj,ctype="application/json; charset=utf-8"):
  raw=jbytes(obj) if ctype.startswith("application/json") else obj
  self.send_response(code); self.send_header("Content-Type",ctype); self.send_header("Content-Length",str(len(raw))); self.send_header("Cache-Control","no-store"); self.send_header("X-Content-Type-Options","nosniff"); self.end_headers(); self.wfile.write(raw)
 def length(self,limit):
  x=self.headers.get("Content-Length","")
  if not x.isdigit() or int(x)<1 or int(x)>limit: raise ValueError("body_size_out_of_range")
  return int(x)
 def json_body(self,limit=MAX_JSON):
  raw=self.rfile.read(self.length(limit))
  try: v=json.loads(raw.decode("utf-8"))
  except (UnicodeDecodeError,json.JSONDecodeError): raise ValueError("invalid_json")
  if not isinstance(v,dict): raise ValueError("json_object_required")
  return v
 def auth(self,role="endpoint"):
  header=self.headers.get("Authorization","")
  if not header.startswith("Bearer ") or len(header)>512: return None
  tok=header[7:]
  if role in ("admin","validator","runner","canonical"):
   expected=os.environ.get({"admin":"NANLM_ADMIN_TOKEN","validator":"NANLM_VALIDATOR_TOKEN","runner":"NANLM_RUNNER_TOKEN","canonical":"NANLM_BOOTSTRAP_TOKEN"}[role],"")
   return {"endpoint_id":role,"scopes":["*"]} if len(expected)>=32 and secrets.compare_digest(tok,expected) else None
  try: th=token_hash(tok)
  except RuntimeError: return None
  db=connect()
  try:
   db.execute("BEGIN IMMEDIATE"); row=db.execute("SELECT * FROM tokens WHERE token_hash=?",(th,)).fetchone()
   if not row or row["revoked"] or row["expires_at"]<=now() or row["used_requests"]>=row["max_requests"]: db.rollback(); return None
   address=row["endpoint_id"]
   owner_device_id=row["owner_device_id"] if "owner_device_id" in row.keys() else None
   if not owner_device_id and address_coordinates(address)["hw"]>=4:
    db.rollback();return None
   lease_id=None
   if owner_device_id:
    lease=db.execute("SELECT lease_id,expires_at FROM device_leases WHERE device_id=? AND address=? AND status='active'",(owner_device_id,address)).fetchone()
    if not lease:
     db.rollback();return None
    # An expired lease may only renew, inspect its own registration, or release.
    # It cannot continue sending observations/data after its slot is eligible
    # for reassignment.
    if lease["expires_at"]<=now() and urlparse(self.path).path not in (
     "/v1/devices/heartbeat","/v1/devices/release","/v1/devices/me"
    ):
     db.rollback();return None
    lease_id=lease["lease_id"]
   claimed=self.headers.get("X-NaN-Address","")
   if claimed and claimed!=address:
    db.rollback(); return None
   db.execute("UPDATE tokens SET used_requests=used_requests+1 WHERE token_hash=?",(th,)); db.commit()
   if owner_device_id:db.execute("UPDATE devices SET last_seen=? WHERE device_id=?",(now(),owner_device_id));db.commit()
   return {"endpoint_id":address,"address":address,"node_point":address_node_point(address),"coordinates":address_coordinates(address),"scopes":json.loads(row["scopes_json"]),"device_id":owner_device_id,"lease_id":lease_id}
  finally: db.close()
 def need(self,role="endpoint"):
  ident=self.auth(role)
  if ident is None: self.reply(401,{"error":"unauthorized"})
  return ident
 def do_GET(self):
  p=urlparse(self.path).path
  if p in ("/","/portal"):
   try: raw=Path(__file__).with_name("portal.html").read_bytes()
   except OSError:return self.reply(503,{"error":"portal_unavailable"})
   return self.reply(200,raw,"text/html; charset=utf-8")
  if p=="/healthz": return self.reply(200,{"status":"ok","service":"nannet","protocol":"nanlm.universal-intake","version":2,"addressing":"nan.global-mesh.v1","bootstrap_endpoints":256,"dataset_quota_bytes":DATASET_QUOTA,"chunk_limit_bytes":CHUNK_BYTES,"training_merge_enabled":bool(os.environ.get("NANLM_BOOTSTRAP_TOKEN")),"keeper_enabled":os.environ.get("DEEPREPO_KEEPER_ENABLED","0")=="1"})
  m=re.fullmatch(r"/v1/training/state/([0-9]{1,3})",p)
  if m:
   if self.need("canonical") is None:return
   node=int(m.group(1))
   if not 1<=node<=256:return self.reply(400,{"error":"node_out_of_range"})
   store=get_merge_store()
   if store is None:return self.reply(503,{"error":"training_merge_not_configured"})
   return self.reply(200,store.snapshot(node))
  m=re.fullmatch(r"/v1/training/receipts/([a-f0-9]{64})",p)
  if m:
   if self.need("canonical") is None:return
   store=get_merge_store()
   if store is None:return self.reply(503,{"error":"training_merge_not_configured"})
   receipt=store.receipt(m.group(1))
   if receipt is None:return self.reply(404,{"error":"training_receipt_not_found"})
   return self.reply(200,receipt)
  if p=="/v1/devices/me":
   x=self.need()
   if x is None:return
   if not x.get("device_id"):return self.reply(403,{"error":"device_registration_required"})
   db=connect()
   try:
    row=db.execute("SELECT d.device_id,d.created_at,d.last_seen,d.status,d.report_json,l.lease_id,l.address,l.issued_at,l.expires_at FROM devices d JOIN device_leases l ON l.device_id=d.device_id AND l.status='active' WHERE d.device_id=?",(x["device_id"],)).fetchone()
    if not row:return self.reply(404,{"error":"active_device_lease_not_found"})
    return self.reply(200,{**dict(row),"system_report":json.loads(row["report_json"])})
   finally:db.close()
  if p=="/v1/address":
   x=self.need()
   if x is None:return
   return self.reply(200,{"address":x["address"],"node_point":x["node_point"],"coordinates":x["coordinates"],"addressing":"nan.global-mesh.v1","transport_authority":os.environ.get("NANNET_PUBLIC_URL","").rstrip("/"),"transport":"https","transport_binding":"bearer-token","head_count":256,"head_index_space":"local-to-endpoint"})
  if p=="/admin/devices":
   if self.need("admin") is None:return
   db=connect()
   try:
    rows=db.execute("SELECT d.device_id,d.created_at,d.last_seen,d.status,d.report_json,l.address,l.lease_id,l.issued_at,l.expires_at FROM devices d LEFT JOIN device_leases l ON l.device_id=d.device_id AND l.status='active' ORDER BY d.last_seen DESC LIMIT 256").fetchall()
    return self.reply(200,{"devices":[{**dict(r),"system_report":json.loads(r["report_json"])} for r in rows]})
   finally:db.close()
  if p=="/admin/device/reports":
   if self.need("admin") is None:return
   db=connect()
   try:
    rows=db.execute("SELECT report_id,device_id,address,created_at,report_type,summary,details,system_json,status FROM device_reports ORDER BY created_at DESC LIMIT 100").fetchall()
    return self.reply(200,{"reports":[{**dict(r),"system_report":json.loads(r["system_json"])} for r in rows]})
   finally:db.close()
  if p=="/admin/training/status":
   if self.need("admin") is None:return
   store=get_merge_store()
   if store is None:return self.reply(503,{"error":"training_merge_not_configured"})
   return self.reply(200,store.status())
  if p=="/admin/keeper/status":
   if self.need("admin") is None:return
   return self.reply(200,dict(KEEPER_STATE))
  if p=="/admin/models/status":
   if self.need("admin") is None:return
   return self.reply(200,{"model":KEEPER_STATE.get("model",{}),"budget":KEEPER_STATE.get("budget",{}),"keeper_action":KEEPER_STATE.get("action","not_started")})
  if p=="/v1/routes":
   x=self.need()
   if x is None:return
   scopes=set(x["scopes"]); ep=x["endpoint_id"]
   visible={k:v for k,v in ROUTES.items() if "*" in scopes or ep in v["audience"] or scopes.intersection(v["audience"])}
   return self.reply(200,{"address":x["address"],"node_point":x["node_point"],"head_count":256,"routes":visible})
  if p=="/internal/datasets":
   if self.need("validator") is None:return
   db=connect()
   try:
    rows=db.execute("SELECT dataset_id,endpoint_id,created_at,expected_chunks,total_bytes,dataset_sha256,status,metadata_json FROM datasets WHERE status='quarantine' ORDER BY created_at LIMIT 32").fetchall()
    return self.reply(200,{"datasets":[{**dict(r),"metadata":json.loads(r["metadata_json"])} for r in rows]})
   finally: db.close()
  if p=="/internal/datasets/committed":
   if self.need("runner") is None:return
   db=connect()
   try:
    rows=db.execute("SELECT dataset_id,endpoint_id,created_at,total_bytes,dataset_sha256,status,committed_generation,validation_json,metadata_json FROM datasets WHERE status='committed' ORDER BY created_at DESC LIMIT 100").fetchall()
    return self.reply(200,{"datasets":[{**dict(r),"metadata":json.loads(r["metadata_json"]),"validation":json.loads(r["validation_json"] or "{}")} for r in rows]})
   finally:db.close()
  if p=="/internal/datasets/validated":
   if self.need("runner") is None:return
   db=connect()
   try:
    rows=db.execute("SELECT dataset_id,endpoint_id,created_at,expected_chunks,total_bytes,dataset_sha256,status,validation_json,metadata_json FROM datasets WHERE status='validated' ORDER BY created_at LIMIT 32").fetchall()
    return self.reply(200,{"datasets":[{**dict(r),"metadata":json.loads(r["metadata_json"]),"validation":json.loads(r["validation_json"] or "{}")} for r in rows]})
   finally: db.close()
  m=re.fullmatch(r"/internal/datasets/([A-Za-z0-9._-]{1,96})/chunks/(\d+)",p)
  if m:
   validator=self.auth("validator"); runner=self.auth("runner")
   if validator is None and runner is None:return self.reply(401,{"error":"unauthorized"})
   db=connect()
   try:
    ds=db.execute("SELECT status FROM datasets WHERE dataset_id=?",(m.group(1),)).fetchone()
    if not ds:return self.reply(404,{"error":"dataset_not_found"})
    if ds["status"]=="committed":return self.reply(410,{"error":"dataset_bytes_released_after_canonical_ingest"})
    if runner is not None and ds["status"]!="validated":return self.reply(403,{"error":"dataset_not_validated"})
    row=db.execute("SELECT blob_path,size_bytes,sha256 FROM chunks WHERE dataset_id=? AND chunk_index=? AND status='stored'",(m.group(1),int(m.group(2)))).fetchone()
   finally: db.close()
   if not row:return self.reply(404,{"error":"chunk_not_found"})
   f=Path(row["blob_path"])
   if not f.is_file():return self.reply(410,{"error":"blob_missing"})
   self.send_response(200); self.send_header("Content-Type","application/octet-stream"); self.send_header("Content-Length",str(row["size_bytes"])); self.send_header("X-Chunk-SHA256",row["sha256"]); self.end_headers()
   with f.open("rb") as stream:
    while True:
     b=stream.read(65536)
     if not b:break
     self.wfile.write(b)
   return
  if p=="/internal/observations":
   if self.need("runner") is None:return
   db=connect()
   try:
    rows=db.execute("SELECT event_id,endpoint_id,received_at,payload_json FROM observations WHERE status='pending' ORDER BY received_at LIMIT 100").fetchall()
    return self.reply(200,{"events":[{"event_id":r["event_id"],"endpoint_id":r["endpoint_id"],"received_at":r["received_at"],"observation":json.loads(r["payload_json"])} for r in rows]})
   finally:db.close()
  return self.reply(404,{"error":"not_found"})
 def do_POST(self):
  p=urlparse(self.path).path
  if p=="/v1/devices/register":
   try:
    d=self.json_body()
    secret=d.get("device_secret",""); report=d.get("system_report")
    if not isinstance(secret,str) or not re.fullmatch(r"[A-Za-z0-9_-]{43,128}",secret):raise ValueError("device_secret_must_be_32_random_bytes_base64url")
    if d.get("consent") is not True or d.get("terms_version")!="nannet-device-registration-v1":raise ValueError("explicit_registration_consent_required")
    if not isinstance(report,dict) or len(jbytes(report))>8192:raise ValueError("bounded_system_report_required")
    required=("platform","os_version","app_version","abi")
    if any(not isinstance(report.get(k),str) or not report[k].strip() or len(report[k])>96 for k in required):raise ValueError("platform_os_app_and_abi_required")
    forbidden={"imei","imsi","serial","serial_number","android_id","mac","mac_address","phone_number","email"}
    if forbidden.intersection(k.lower() for k in report):raise ValueError("persistent_hardware_or_personal_identifiers_not_collected")
    safe_report={k:report[k] for k in ("platform","os_version","app_version","build_id","device_model","manufacturer","abi","cpu_cores","ram_mb","storage_free_mb","capabilities","locale") if k in report}
    if any(isinstance(safe_report.get(k),bool) or not isinstance(safe_report.get(k),int) or safe_report[k]<0 or safe_report[k]>2**31-1 for k in ("cpu_cores","ram_mb","storage_free_mb") if k in safe_report):raise ValueError("invalid_system_capacity_value")
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:100]})
   key_hash=token_hash(secret);device_id=hashlib.sha256(key_hash.encode()).hexdigest()[:32];timestamp=now()
   lease_seconds=max(3600,min(2592000,int(os.environ.get("NANLM_DEVICE_LEASE_SECONDS","86400"))))
   db=connect();token="nnt_"+secrets.token_urlsafe(36);lease_id=None;address=None
   try:
    db.execute("BEGIN IMMEDIATE")
    device=db.execute("SELECT * FROM devices WHERE device_id=? AND key_hash=?",(device_id,key_hash)).fetchone()
    if not device:
     db.execute("INSERT INTO devices(device_id,key_hash,created_at,last_seen,status,report_json,terms_version,consent_at) VALUES(?,?,?,?,?,?,?,?)",(device_id,key_hash,timestamp,timestamp,"registered",jbytes(safe_report).decode(),"nannet-device-registration-v1",timestamp))
    else:
     db.execute("UPDATE devices SET last_seen=?,status='registered',report_json=? WHERE device_id=?",(timestamp,jbytes(safe_report).decode(),device_id))
    lease=db.execute("SELECT * FROM device_leases WHERE device_id=? AND status='active'",(device_id,)).fetchone()
    if lease and lease["expires_at"]<=timestamp:
     pending=db.execute("SELECT 1 FROM datasets WHERE endpoint_id=? AND status IN ('uploading','quarantine','validated') LIMIT 1",(lease["address"],)).fetchone() or db.execute("SELECT 1 FROM observations WHERE endpoint_id=? AND status='pending' LIMIT 1",(lease["address"],)).fetchone()
     if pending:
      db.execute("UPDATE device_leases SET expires_at=? WHERE lease_id=?",(timestamp+lease_seconds,lease["lease_id"]))
     else:
      db.execute("UPDATE device_leases SET status='expired',released_at=? WHERE lease_id=?",(timestamp,lease["lease_id"]))
      db.execute("UPDATE devices SET status='expired',last_seen=? WHERE device_id=?",(timestamp,device_id))
      db.execute("UPDATE tokens SET revoked=1 WHERE owner_device_id=?",(device_id,))
      lease=None
    if lease:
     address=lease["address"];lease_id=lease["lease_id"]
     db.execute("UPDATE device_leases SET expires_at=? WHERE lease_id=?",(timestamp+lease_seconds,lease_id))
    else:
     for hw in range(8,255):
      candidate=nan_address(0,0,0,0,hw)
      active=db.execute("SELECT lease_id,expires_at,device_id FROM device_leases WHERE address=? AND status='active'",(candidate,)).fetchone()
      if active and active["expires_at"]<=timestamp:
       pending=db.execute("SELECT 1 FROM datasets WHERE endpoint_id=? AND status IN ('uploading','quarantine','validated') LIMIT 1",(candidate,)).fetchone() or db.execute("SELECT 1 FROM observations WHERE endpoint_id=? AND status='pending' LIMIT 1",(candidate,)).fetchone()
       if not pending:
        db.execute("UPDATE device_leases SET status='expired',released_at=? WHERE lease_id=?",(timestamp,active["lease_id"]))
        db.execute("UPDATE devices SET status='expired',last_seen=? WHERE device_id=?",(timestamp,active["device_id"]))
        db.execute("UPDATE tokens SET revoked=1 WHERE endpoint_id=?",(candidate,))
        active=None
      if not active:
       address=candidate;lease_id=secrets.token_urlsafe(24)
       db.execute("INSERT INTO device_leases(lease_id,address,device_id,issued_at,expires_at,status) VALUES(?,?,?,?,?,'active')",(lease_id,address,device_id,timestamp,timestamp+lease_seconds))
       break
     if address is None:db.rollback();return self.reply(503,{"error":"no_device_slots_available","reserved_hw_slots":[0,1,2,3,4,5,6,7],"dynamic_range":"HW8-HW254"})
    db.execute("UPDATE tokens SET revoked=1 WHERE owner_device_id=?",(device_id,))
    scopes=["intake","dataset","observation","heartbeat","n16t","device.report"]
    db.execute("INSERT INTO tokens(token_hash,endpoint_id,scopes_json,expires_at,max_requests,created_at,owner_device_id) VALUES(?,?,?,?,?,?,?)",(token_hash(token),address,json.dumps(scopes),timestamp+min(max(lease_seconds*4,604800),2592000),1000000,timestamp,device_id))
    db.execute("UPDATE devices SET status='active',last_seen=? WHERE device_id=?",(timestamp,device_id))
    db.commit()
   except sqlite3.IntegrityError:
    db.rollback();return self.reply(409,{"error":"device_or_node_lease_conflict_retry_registration"})
   finally:db.close()
   return self.reply(201,{"device_id":device_id,"address":address,"node_point":address_node_point(address),"coordinates":address_coordinates(address),"lease_id":lease_id,"lease_expires_at":timestamp+lease_seconds,"token":token,"scopes":scopes,"head_count":256,"identity_model":"installation-key","mac_address_collected":False})
  if p=="/v1/devices/heartbeat":
   x=self.need()
   if x is None:return
   if "heartbeat" not in x["scopes"] and "*" not in x["scopes"]:return self.reply(403,{"error":"scope_denied"})
   if not x.get("device_id"):return self.reply(403,{"error":"device_registration_required"})
   seconds=max(3600,min(2592000,int(os.environ.get("NANLM_DEVICE_LEASE_SECONDS","86400"))))
   db=connect()
   try:
    n=db.execute("UPDATE device_leases SET expires_at=? WHERE lease_id=? AND device_id=? AND status='active'",(now()+seconds,x["lease_id"],x["device_id"])).rowcount
    db.execute("UPDATE devices SET last_seen=?,status='active' WHERE device_id=?",(now(),x["device_id"]));db.commit()
   finally:db.close()
   if not n:return self.reply(409,{"error":"lease_not_active"})
   return self.reply(200,{"state":"active","address":x["address"],"lease_id":x["lease_id"],"lease_expires_at":now()+seconds})
  if p=="/v1/devices/release":
   x=self.need()
   if x is None:return
   if not x.get("device_id"):return self.reply(403,{"error":"device_registration_required"})
   db=connect()
   try:
    pending=db.execute("SELECT dataset_id,status FROM datasets WHERE endpoint_id=? AND status IN ('uploading','quarantine','validated') LIMIT 1",(x["address"],)).fetchone()
    evidence=db.execute("SELECT event_id FROM observations WHERE endpoint_id=? AND status='pending' LIMIT 1",(x["address"],)).fetchone()
    if pending or evidence:return self.reply(409,{"error":"pending_work_must_be_committed_or_rejected_before_release","dataset_id":pending["dataset_id"] if pending else None,"pending_observation":bool(evidence)})
    db.execute("UPDATE device_leases SET status='released',released_at=? WHERE lease_id=? AND device_id=? AND status='active'",(now(),x["lease_id"],x["device_id"]))
    db.execute("UPDATE devices SET status='released',last_seen=? WHERE device_id=?",(now(),x["device_id"]))
    db.execute("UPDATE tokens SET revoked=1 WHERE owner_device_id=?",(x["device_id"],));db.commit()
   finally:db.close()
   return self.reply(200,{"state":"released","address":x["address"],"lease_id":x["lease_id"],"token_revoked":True,"node_available":True})
  if p=="/v1/devices/report":
   x=self.need()
   if x is None:return
   if "device.report" not in x["scopes"] and "*" not in x["scopes"]:return self.reply(403,{"error":"scope_denied"})
   if not x.get("device_id"):return self.reply(403,{"error":"device_registration_required"})
   try:
    d=self.json_body();kind=d.get("report_type");summary=d.get("summary","");details=d.get("details","");system=d.get("system_report",{})
    if kind not in ("device_error","system_error","network_error","security_concern","other"):raise ValueError("invalid_report_type")
    if not isinstance(summary,str) or not summary.strip() or len(summary)>240:raise ValueError("summary_required_max_240")
    if not isinstance(details,str) or len(details)>4000 or not isinstance(system,dict) or len(jbytes(system))>8192:raise ValueError("report_details_or_system_snapshot_invalid")
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:100]})
   report_id=secrets.token_urlsafe(18);db=connect()
   try:
    db.execute("INSERT INTO device_reports(report_id,device_id,address,created_at,report_type,summary,details,system_json) VALUES(?,?,?,?,?,?,?,?)",(report_id,x["device_id"],x["address"],now(),kind,summary.strip(),details, jbytes(system).decode()));db.commit()
   finally:db.close()
   return self.reply(202,{"report_id":report_id,"state":"received","address":x["address"]})
  commit_match=re.fullmatch(r"/internal/datasets/([A-Za-z0-9._-]{1,96})/commit",p)
  if commit_match:
   if self.need("runner") is None:return
   try:
    data=self.json_body();generation=data.get("generation");digest=data.get("dataset_sha256")
    if isinstance(generation,bool) or not isinstance(generation,int) or generation<1 or not isinstance(digest,str) or not HEX.fullmatch(digest):raise ValueError("generation_and_dataset_sha256_required")
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:80]})
   dsid=commit_match.group(1);db=connect();paths=[]
   try:
    db.execute("BEGIN IMMEDIATE")
    ds=db.execute("SELECT status,dataset_sha256,committed_generation FROM datasets WHERE dataset_id=?",(dsid,)).fetchone()
    if not ds:db.rollback();return self.reply(404,{"error":"dataset_not_found"})
    if ds["status"]=="committed":
     db.rollback()
     if ds["dataset_sha256"]==digest and ds["committed_generation"]==generation:return self.reply(200,{"dataset_id":dsid,"state":"committed","generation":generation,"duplicate_noop":True,"staging_bytes_released":True})
     return self.reply(409,{"error":"dataset_already_committed_with_different_receipt"})
    if ds["status"]!="validated":db.rollback();return self.reply(409,{"error":"dataset_not_validated"})
    if not secrets.compare_digest(ds["dataset_sha256"] or "",digest):db.rollback();return self.reply(422,{"error":"dataset_digest_receipt_mismatch"})
    paths=db.execute("SELECT blob_path FROM chunks WHERE dataset_id=?",(dsid,)).fetchall()
    report=json.loads(db.execute("SELECT validation_json FROM datasets WHERE dataset_id=?",(dsid,)).fetchone()[0] or "{}")
    report["canonical_ingest"]={"generation":generation,"dataset_sha256":digest,"committed_at":now(),"consumer":"nanlm-runner-ring"}
    db.execute("UPDATE datasets SET status='committed',committed_generation=?,validation_json=? WHERE dataset_id=?",(generation,jbytes(report).decode(),dsid))
    db.execute("DELETE FROM chunks WHERE dataset_id=?",(dsid,));db.commit()
   finally:db.close()
   removed=0
   for row in paths:
    try:Path(row["blob_path"]).unlink(missing_ok=True);removed+=1
    except OSError:pass
   return self.reply(200,{"dataset_id":dsid,"state":"committed","generation":generation,"staging_chunks_removed":removed,"staging_bytes_released":True})
  if p=="/v1/training/merge":
   if self.need("canonical") is None:return
   store=get_merge_store()
   if store is None:return self.reply(503,{"error":"training_merge_not_configured"})
   try:
    payload=self.json_body(1_048_576)
    if payload.get("source_endpoint")!="bootstrap":return self.reply(403,{"error":"only_canonical_runner_may_merge"})
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:80]})
   status,body=store.merge(payload,self.headers.get("Idempotency-Key",""),"bootstrap")
   return self.reply(int(status),body)
  if p=="/n16t":
   x=self.need()
   if x is None:return
   if "n16t" not in x["scopes"] and "*" not in x["scopes"]:return self.reply(403,{"error":"scope_denied"})
   media=self.headers.get("Content-Type","").split(";",1)[0].strip()
   if media not in ("application/vnd.nan16.n16t","application/x-n16t"):return self.reply(415,{"error":"n16t_content_type_required"})
   try:
    size=self.length(65572)
    frame=self.rfile.read(size)
    if len(frame)<36:return self.reply(400,{"error":"truncated_n16t_frame"})
   except ValueError as e:return self.reply(400,{"error":str(e)})
   peer=os.environ.get("NANLM_N16T_PEER_URL","").rstrip("/")
   peer_token=os.environ.get("NANLM_N16T_PEER_TOKEN","")
   if not peer or len(peer_token)<32:return self.reply(503,{"error":"n16t_peer_not_configured"})
   if not peer.startswith("https://"):return self.reply(503,{"error":"n16t_peer_must_use_https"})
   try:
    req=Request(peer+"/n16t",data=frame,headers={"Authorization":"Bearer "+peer_token,"Content-Type":"application/vnd.nan16.n16t","Accept":"application/vnd.nan16.n16t"},method="POST")
    with urlopen(req,timeout=30) as response:
     response_type=response.headers.get("Content-Type","").split(";",1)[0].strip()
     reply=response.read(65573)
    if response_type!="application/vnd.nan16.n16t" or not 36<=len(reply)<=65572:return self.reply(502,{"error":"invalid_n16t_peer_response"})
    return self.reply(200,reply,"application/vnd.nan16.n16t")
   except (HTTPError,URLError,OSError,TimeoutError):
    return self.reply(502,{"error":"n16t_peer_unavailable"})
  if p=="/admin/tokens":
   if self.need("admin") is None:return
   try:
    d=self.json_body(); endpoint=d.get("address"); scopes=d.get("scopes",["intake"]); ttl=int(d.get("ttl_seconds",86400)); quota=int(d.get("max_requests",10000))
    if not valid_nan_address(endpoint) or endpoint not in ENDPOINTS or address_coordinates(endpoint)["hw"]>=4 or not isinstance(scopes,list) or not scopes or any(s not in {"intake","dataset","observation","heartbeat","n16t","device.report"} for s in scopes):raise ValueError("invalid_nan_address_or_scopes")
    if not 60<=ttl<=7776000 or not 1<=quota<=10000000:raise ValueError("token_policy_out_of_range")
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:80]})
   token="nnt_"+secrets.token_urlsafe(36); db=connect()
   try: db.execute("INSERT INTO tokens(token_hash,endpoint_id,scopes_json,expires_at,max_requests,created_at) VALUES(?,?,?,?,?,?)",(token_hash(token),endpoint,json.dumps(sorted(set(scopes))),now()+ttl,quota,now())); db.commit()
   finally:db.close()
   return self.reply(201,{"token":token,"address":endpoint,"endpoint_id":endpoint,"scopes":sorted(set(scopes)),"expires_at":now()+ttl,"max_requests":quota})
  if p=="/internal/observations/ack":
   if self.need("runner") is None:return
   try:
    ids=self.json_body().get("event_ids")
    if not isinstance(ids,list) or len(ids)>100 or any(not isinstance(v,str) or not EVENT_ID.fullmatch(v) for v in ids):raise ValueError("invalid_event_ids")
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:80]})
   db=connect()
   try:
    changed=0
    for eid in ids: changed+=db.execute("UPDATE observations SET status='folded' WHERE event_id=? AND status='pending'",(eid,)).rowcount
    db.commit()
   finally:db.close()
   return self.reply(200,{"folded":changed})
  if p=="/v1/intake/route":
   x=self.need()
   if x is None:return
   if not ({"intake","observation"}&set(x["scopes"]) or "*" in x["scopes"]):return self.reply(403,{"error":"scope_denied"})
   try:
    d=self.json_body()
    required=("universe","node","layer","control_point","base_generation","epoch","entries","digest")
    if any(k not in d for k in required):raise ValueError("route_diff_fields_required")
    integers=("universe","node","layer","control_point","base_generation","epoch")
    if any(isinstance(d[k],bool) or not isinstance(d[k],int) or d[k]<0 for k in integers):raise ValueError("invalid_route_diff_integer")
    if d["universe"]!=x["coordinates"]["bs"] or d["node"]!=x["node_point"]:raise ValueError("route_diff_address_mismatch")
    if d["layer"]>255 or not 1<=d["control_point"]<=256 or d["base_generation"]>2**63-1 or d["epoch"]>2**63-1:raise ValueError("route_diff_value_out_of_range")
    entries=d["entries"]
    if not isinstance(entries,list) or len(entries)>256 or any(not isinstance(item,dict) for item in entries):raise ValueError("invalid_route_entries")
    digest=d["digest"]
    if not isinstance(digest,str) or not HEX.fullmatch(digest):raise ValueError("invalid_route_digest")
    canonical={k:d[k] for k in required if k!="digest"}
    if hashlib.sha256(jbytes(canonical)).hexdigest()!=digest:raise ValueError("route_digest_mismatch")
    payload={"protocol":"nanlm.route-diff","version":1,"universe":d["universe"],"node":d["node"],"layer":d["layer"],"control_point":d["control_point"],"base_generation":d["base_generation"],"epoch":d["epoch"],"entries":entries,"digest":digest,"outcome_verified":False}
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:80]})
   db=connect()
   try:
    db.execute("INSERT OR IGNORE INTO observations(event_id,endpoint_id,received_at,payload_json) VALUES(?,?,?,?)",(digest,x["endpoint_id"],now(),json.dumps(payload,sort_keys=True,separators=(",",":"))));inserted=db.execute("SELECT changes()").fetchone()[0];db.commit()
   finally:db.close()
   return self.reply(202 if inserted else 200,{"event_id":digest,"endpoint_id":x["endpoint_id"],"state":"pending_unverified" if inserted else "duplicate_noop","outcome_verified":False,"base_generation":d["base_generation"]})
  if p=="/v1/observations":
   x=self.need()
   if x is None:return
   if not ({"intake","observation"}&set(x["scopes"]) or "*" in x["scopes"]):return self.reply(403,{"error":"scope_denied"})
   try:
    d=self.json_body(); eid=d.get("event_id"); gen=d.get("base_generation"); heads=d.get("active_heads",[])
    if d.get("protocol")!="nanlm.endpoint-observation" or d.get("version")!=1:raise ValueError("unsupported_protocol")
    if not isinstance(eid,str) or not EVENT_ID.fullmatch(eid):raise ValueError("invalid_event_id")
    if isinstance(gen,bool) or not isinstance(gen,int) or gen<0:raise ValueError("invalid_base_generation")
    if not isinstance(heads,list) or len(heads)>256 or any(isinstance(h,bool) or not isinstance(h,int) or not 0<=h<=255 for h in heads):raise ValueError("invalid_active_heads")
    if d.get("outcome_verified",False) is not False or "correct" in d or "head_deltas" in d:raise ValueError("endpoint_cannot_assert_correctness")
    payload={"protocol":"nanlm.endpoint-observation","version":1,"event_id":eid,"base_generation":gen,"active_heads":sorted(set(heads)),"outcome_verified":False}
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:80]})
   db=connect()
   try:
    db.execute("INSERT OR IGNORE INTO observations(event_id,endpoint_id,received_at,payload_json) VALUES(?,?,?,?)",(eid,x["endpoint_id"],now(),json.dumps(payload,sort_keys=True,separators=(",",":")))); inserted=db.execute("SELECT changes()").fetchone()[0]; db.commit()
   finally:db.close()
   return self.reply(202 if inserted else 200,{"event_id":eid,"endpoint_id":x["endpoint_id"],"state":"pending_unverified" if inserted else "duplicate_noop","outcome_verified":False})
  m=re.fullmatch(r"/v1/datasets/([A-Za-z0-9._-]{1,96})/begin",p)
  if m:
   x=self.need()
   if x is None:return
   if not ({"intake","dataset"}&set(x["scopes"]) or "*" in x["scopes"]):return self.reply(403,{"error":"scope_denied"})
   try:
    data=self.json_body();count=int(data.get("chunk_count",0));meta=data.get("metadata")
    if not 1<=count<=100000:raise ValueError("invalid_chunk_count")
    if not isinstance(meta,dict) or meta.get("protocol")!="nanlm.dataset" or meta.get("version")!=1:raise ValueError("dataset_metadata_protocol_required")
    content_type=meta.get("content_type");encoding=meta.get("encoding");license_name=meta.get("license");provenance=meta.get("provenance")
    if not isinstance(content_type,str) or not 1<=len(content_type)<=128:raise ValueError("content_type_required")
    if not isinstance(encoding,str) or not 1<=len(encoding)<=64:raise ValueError("encoding_required")
    if not isinstance(license_name,str) or not 1<=len(license_name.strip())<=256:raise ValueError("license_required")
    if not isinstance(provenance,str) or not 1<=len(provenance.strip())<=512:raise ValueError("provenance_required")
    clean={"protocol":"nanlm.dataset","version":1,"content_type":content_type,"encoding":encoding,"format":str(meta.get("format","plain-text/utf8"))[:32],"license":license_name.strip(),"provenance":provenance.strip(),"split":str(meta.get("split","unassigned"))[:32],"source":str(meta.get("source",""))[:1024]}
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:80]})
   db=connect()
   try:db.execute("INSERT INTO datasets(dataset_id,endpoint_id,created_at,expected_chunks,metadata_json) VALUES(?,?,?,?,?)",(m.group(1),x["endpoint_id"],now(),count,json.dumps(clean,sort_keys=True)));db.commit()
   except sqlite3.IntegrityError:return self.reply(409,{"error":"dataset_id_exists"})
   finally:db.close()
   return self.reply(201,{"dataset_id":m.group(1),"state":"uploading","chunk_limit_bytes":CHUNK_BYTES,"dataset_quota_bytes":DATASET_QUOTA})
  m=re.fullmatch(r"/v1/datasets/([A-Za-z0-9._-]{1,96})/seal",p)
  if m:
   x=self.need()
   if x is None:return
   if not ({"intake","dataset"}&set(x["scopes"]) or "*" in x["scopes"]):return self.reply(403,{"error":"scope_denied"})
   try:
    d=self.json_body(); total=int(d.get("total_bytes",-1)); sha=d.get("sha256")
    if total<1 or (sha is not None and (not isinstance(sha,str) or not HEX.fullmatch(sha))):raise ValueError("invalid_manifest")
   except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:80]})
   db=connect()
   try:
    ds=db.execute("SELECT * FROM datasets WHERE dataset_id=? AND endpoint_id=?",(m.group(1),x["endpoint_id"])).fetchone()
    if not ds:return self.reply(404,{"error":"dataset_not_found"})
    chunks=db.execute("SELECT chunk_index,size_bytes,blob_path FROM chunks WHERE dataset_id=? AND status='stored' ORDER BY chunk_index",(m.group(1),)).fetchall()
    if len(chunks)!=ds["expected_chunks"] or [c["chunk_index"] for c in chunks]!=list(range(ds["expected_chunks"])):return self.reply(409,{"error":"chunks_incomplete"})
    if sum(c["size_bytes"] for c in chunks)!=total:return self.reply(409,{"error":"total_size_mismatch"})
    h=hashlib.sha256()
    for c in chunks:
     with open(c["blob_path"],"rb") as f:
      while True:
       b=f.read(65536)
       if not b:break
       h.update(b)
    actual=h.hexdigest()
    if sha is not None and actual!=sha:return self.reply(422,{"error":"dataset_digest_mismatch"})
    db.execute("UPDATE datasets SET total_bytes=?,dataset_sha256=?,status='quarantine' WHERE dataset_id=?",(total,actual,m.group(1)));db.commit()
   finally:db.close()
   return self.reply(202,{"dataset_id":m.group(1),"state":"quarantine_pending_external_validation","sha256":actual,"bytes":total,"digest_computed_by":"nannet"})
  return self.reply(404,{"error":"not_found"})
 def do_PUT(self):
  m=re.fullmatch(r"/v1/datasets/([A-Za-z0-9._-]{1,96})/chunks/(\d+)",urlparse(self.path).path)
  if not m:return self.reply(404,{"error":"not_found"})
  x=self.need()
  if x is None:return
  if not ({"intake","dataset"}&set(x["scopes"]) or "*" in x["scopes"]):return self.reply(403,{"error":"scope_denied"})
  try:size=self.length(CHUNK_BYTES)
  except ValueError as e:return self.reply(400,{"error":str(e)})
  expected=self.headers.get("X-Chunk-SHA256","")
  if not HEX.fullmatch(expected):return self.reply(400,{"error":"chunk_sha256_required"})
  dsid,idx=m.group(1),int(m.group(2)); db=connect(); temp=None; final=None
  try:
   db.execute("BEGIN IMMEDIATE"); ds=db.execute("SELECT * FROM datasets WHERE dataset_id=? AND endpoint_id=? AND status='uploading'",(dsid,x["endpoint_id"])).fetchone()
   if not ds:db.rollback();return self.reply(404,{"error":"dataset_not_uploading"})
   if idx>=ds["expected_chunks"]:db.rollback();return self.reply(400,{"error":"chunk_index_out_of_range"})
   if db.execute("SELECT 1 FROM chunks WHERE dataset_id=? AND chunk_index=?",(dsid,idx)).fetchone():db.rollback();return self.reply(409,{"error":"chunk_already_exists"})
   used=db.execute("SELECT COALESCE(SUM(size_bytes),0) FROM chunks WHERE status IN ('receiving','stored')").fetchone()[0]
   if used+size>DATASET_QUOTA:db.rollback();return self.reply(507,{"error":"disk_quota_exceeded"})
   final=BLOBS/(hashlib.sha256((dsid+":"+str(idx)).encode()).hexdigest()+".blob")
   db.execute("INSERT INTO chunks VALUES(?,?,?,?,?,'receiving')",(dsid,idx,expected,size,str(final)));db.commit()
   fd,temp=tempfile.mkstemp(prefix="part-",dir=str(BLOBS)); h=hashlib.sha256()
   with os.fdopen(fd,"wb") as out:
    left=size
    while left:
     b=self.rfile.read(min(65536,left))
     if not b:raise ValueError("truncated_chunk")
     out.write(b);h.update(b);left-=len(b)
    out.flush();os.fsync(out.fileno())
   if h.hexdigest()!=expected:raise ValueError("chunk_digest_mismatch")
   os.replace(temp,final);temp=None
   db.execute("UPDATE chunks SET status='stored' WHERE dataset_id=? AND chunk_index=?",(dsid,idx));db.commit()
   return self.reply(201,{"dataset_id":dsid,"chunk_index":idx,"bytes":size,"sha256":expected})
  except (OSError,ValueError) as e:
   if temp and os.path.exists(temp):os.unlink(temp)
   if final and final.exists():final.unlink()
   db.execute("DELETE FROM chunks WHERE dataset_id=? AND chunk_index=? AND status='receiving'",(dsid,idx));db.commit()
   return self.reply(400,{"error":str(e)[:80]})
  finally:db.close()
 def do_PATCH(self):
  m=re.fullmatch(r"/internal/datasets/([A-Za-z0-9._-]{1,96})/validation",urlparse(self.path).path)
  if not m:return self.reply(404,{"error":"not_found"})
  if self.need("validator") is None:return
  try:
   d=self.json_body(); passed=d.get("passed"); report=d.get("report",{})
   if not isinstance(passed,bool) or not isinstance(report,dict) or len(jbytes(report))>MAX_JSON:raise ValueError("invalid_validation_result")
  except (ValueError,TypeError) as e:return self.reply(400,{"error":str(e)[:80]})
  db=connect()
  try:
   state="validated" if passed else "rejected"
   n=db.execute("UPDATE datasets SET status=?,validation_json=?,last_error=? WHERE dataset_id=? AND status='quarantine'",(state,jbytes(report).decode(),None if passed else "external_validation_failed",m.group(1))).rowcount;db.commit()
  finally:db.close()
  if not n:return self.reply(409,{"error":"dataset_not_in_quarantine"})
  return self.reply(200,{"dataset_id":m.group(1),"state":state,"training_eligible":passed})
 def do_DELETE(self):
  m=re.fullmatch(r"/admin/datasets/([A-Za-z0-9._-]{1,96})",urlparse(self.path).path)
  if not m:return self.reply(404,{"error":"not_found"})
  if self.need("admin") is None:return
  db=connect()
  try:
   ds=db.execute("SELECT status FROM datasets WHERE dataset_id=?",(m.group(1),)).fetchone()
   if not ds:return self.reply(404,{"error":"dataset_not_found"})
   if ds["status"]=="validated":return self.reply(409,{"error":"validated_dataset_requires_retention_workflow"})
   paths=db.execute("SELECT blob_path FROM chunks WHERE dataset_id=?",(m.group(1),)).fetchall()
   db.execute("DELETE FROM chunks WHERE dataset_id=?",(m.group(1),));db.execute("DELETE FROM datasets WHERE dataset_id=?",(m.group(1),));db.commit()
   for r in paths:Path(r["blob_path"]).unlink(missing_ok=True)
  finally:db.close()
  return self.reply(200,{"deleted":m.group(1)})
 def do_OPTIONS(self):
  self.send_response(204);self.send_header("Allow","GET,POST,PUT,PATCH,DELETE,OPTIONS");self.send_header("Content-Length","0");self.end_headers()

def start_deeprepo_keeper():
 if os.environ.get("DEEPREPO_KEEPER_ENABLED","0")!="1":return
 for name in ("GH_TOKEN","DEEPREPO_MAIN","DEEPREPO_RAM","DEEPREPO_VRAM"):
  if not os.environ.get(name):raise SystemExit(name+" is required when DEEPREPO_KEEPER_ENABLED=1")
 def run():
  global KEEPER_STATE
  try:
   from deepcore.runtime import Env
   from deepcore.cli import _keeper_tick
   env=Env(writer=True,cache_pages=8,kv_cache_pages=8)
   interval=max(60,int(os.environ.get("KEEPER_INTERVAL","600")))
   KEEPER_STATE.update({"enabled":True,"status":"running","started_at":now()})
   while True:
    try:
     result=_keeper_tick(env)
     mi=env.model_info() or {}
     KEEPER_STATE.update({"enabled":True,"status":"running","last_tick":now(),"action":result.get("action","idle"),"quota_paused":bool(result.get("quota_paused")),"model":{k:mi.get(k) for k in ("key","ready","size","weight_pages")},"budget":env.budget.snapshot()})
     time.sleep(1800 if result.get("quota_paused") else interval)
    except Exception as exc:
     KEEPER_STATE.update({"enabled":True,"status":"degraded","last_tick":now(),"last_error":type(exc).__name__})
     time.sleep(interval)
  except Exception as exc:
   KEEPER_STATE.update({"enabled":False,"status":"failed","last_error":type(exc).__name__})
   print("DeepRepo keeper failed: "+type(exc).__name__,flush=True)
 threading.Thread(target=run,name="deeprepo-keeper",daemon=True).start()

def get_merge_store():
 global MERGE_STORE
 token=os.environ.get("NANLM_BOOTSTRAP_TOKEN","")
 if not token:return None
 if MERGE_STORE is None:
  from training_merge import MergeStore
  root=Path(os.environ.get("NANLM_MERGE_ROOT",str(ROOT/"merge")))
  MERGE_STORE=MergeStore(root,{"bootstrap":token})
 return MERGE_STORE

def main():
 for name in ("NANLM_ADMIN_TOKEN","NANLM_VALIDATOR_TOKEN","NANLM_RUNNER_TOKEN","NANLM_TOKEN_PEPPER","NANLM_BOOTSTRAP_TOKEN"):
  if len(os.environ.get(name,""))<32:raise SystemExit(name+" must be a server-side secret of at least 32 characters")
 ROOT.mkdir(parents=True,exist_ok=True);BLOBS.mkdir(parents=True,exist_ok=True);connect().close()
 start_deeprepo_keeper()
 port=int(os.environ.get("PORT",os.environ.get("NANLM_PORT","8000")))
 print("NANNET listening on 0.0.0.0:%d; disk quota=%d; chunk=%d"%(port,DATASET_QUOTA,CHUNK_BYTES),flush=True)
 BoundedHTTPServer(("0.0.0.0",port),Handler).serve_forever()
if __name__=="__main__":main()
