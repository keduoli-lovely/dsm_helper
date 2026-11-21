"""本地伪 DSM WebAPI，用于在没有真实群晖时验证登录与各页面数据解析。

用法: python tools/mock_dsm.py [port]
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

SID = "MOCKSID123"
STATE = {"logged_in": False}


def api_info():
    return {
        name: {"path": "entry.cgi", "minVersion": 1, "maxVersion": 3}
        for name in [
            "SYNO.API.Auth",
            "SYNO.Core.System",
            "SYNO.Core.System.Utilization",
            "SYNO.Storage.CGI.Storage",
            "SYNO.FileStation.List",
            "SYNO.FileStation.CreateFolder",
            "SYNO.FileStation.Rename",
            "SYNO.FileStation.Delete",
            "SYNO.FileStation.Upload",
            "SYNO.DownloadStation.Task",
            "SYNO.Core.Package",
            "SYNO.Core.Package.Control",
            "SYNO.Core.User",
            "SYNO.Core.SyslogClient.Log",
            "SYNO.Core.TaskScheduler",
            "SYNO.Core.Terminal",
        ]
    }


def system_info():
    return {
        "model": "DS220+",
        "serial": "MOCK0001",
        "firmware_ver": "DSM 7.2.1-69057",
        "up_time": 86400 * 3 + 3600,
        "temperature": 48,
        "cpu_cores": 2,
        "cpu_series": "Intel Celeron J4025",
        "ram_size": 2048,
        "hostname": "mock-nas",
    }


def utilization():
    t = time.time()
    return {
        "cpu": {"user": 18 + (t % 7), "system": 6, "other": 1},
        "memory": {"memory_size": 2048, "avail_real": 1180, "total_real": 2048},
        "network": [{"device": "eth0", "rx": 2_400_000, "tx": 320_000}],
        "disk": {
            "total": [{"device": "total", "read": 8_400_000, "write": 2_100_000, "utilization": 23}],
            "disk": [{"device": "sda", "read": 5_100_000, "write": 1_200_000, "utilization": 18}],
        },
        "space": {"total": {"total": 4000000000000, "used": 2400000000000}},
    }


SHARES = [
    {"name": "video", "path": "/video", "additional": {"size": 120000000000, "owner": {"user": "admin"}}},
    {"name": "photo", "path": "/photo", "additional": {"size": 42000000000, "owner": {"user": "admin"}}},
    {"name": "home", "path": "/home", "additional": {"size": 3000000000, "owner": {"user": "admin"}}},
]

FILES = {
    "/video": [
        {"name": "Movies", "path": "/video/Movies", "isdir": True, "additional": {"time": {"mtime": int(time.time())}}},
        {"name": "demo.mkv", "path": "/video/demo.mkv", "isdir": False,
         "additional": {"size": 2500000000, "time": {"mtime": int(time.time())}, "owner": {"user": "admin"}}},
    ],
    "/video/Movies": [
        {"name": "Interstellar.2014.mkv", "path": "/video/Movies/Interstellar.2014.mkv", "isdir": False,
         "additional": {"size": 18000000000, "time": {"mtime": int(time.time())}}},
    ],
    "/photo": [
        {"name": "2025", "path": "/photo/2025", "isdir": True, "additional": {"time": {"mtime": int(time.time())}}},
        {"name": "cover.jpg", "path": "/photo/cover.jpg", "isdir": False,
         "additional": {"size": 2400000, "time": {"mtime": int(time.time())}}},
    ],
    "/photo/2025": [],
    "/home": [],
}

TASKS = [
    {"id": "dbid_1", "title": "Mock.Task.2160p.mkv", "status": "downloading", "size": 8000000000,
     "additional": {"transfer": {"size_downloaded": 3200000000, "speed_download": 5400000}, "detail": {"destination": "/video"}}},
    {"id": "dbid_2", "title": "Mock.Finished.iso", "status": "finished", "size": 2000000000,
     "additional": {"transfer": {"size_downloaded": 2000000000, "speed_download": 0}, "detail": {"destination": "/video"}}},
]

PACKAGES = [
    {"id": "SynologyPhotos", "name": "Synology Photos", "version": "1.7.1-0819", "status": "running"},
    {"id": "DownloadStation", "name": "Download Station", "version": "4.0.6-3829", "status": "running"},
    {"id": "Docker", "name": "Container Manager", "version": "24.0.2-1535", "status": "stopped"},
]


def storage():
    return {
        "volumes": [
            {"id": "volume_1", "display_name": "存储空间 1", "status": "normal", "fs_type": "btrfs", "raid_type": "SHR",
             "size": {"total": 4000000000000, "used": 2400000000000}}
        ],
        "disks": [
            {"id": "sata1", "model": "WD40EFRX", "size_total": 4000787030016, "status": "normal", "temp": 35},
            {"id": "sata2", "model": "WD40EFRX", "size_total": 4000787030016, "status": "normal", "temp": 37},
        ],
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _form(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8") if length else ""
        if "multipart/form-data" in (self.headers.get("Content-Type") or ""):
            return {}
        return {k: v[0] for k, v in parse_qs(body, keep_blank_values=True).items()}

    def _parsed(self, params):
        out = {}
        for k, v in params.items():
            if isinstance(v, str) and (v.startswith("[") or v.startswith("{")):
                try:
                    out[k] = json.loads(v)
                    continue
                except Exception:
                    pass
            out[k] = v
        return out

    def _send(self, payload, status=200):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Set-Cookie", "did=mockdid123; Path=/")
        self.end_headers()
        self.wfile.write(data)

    def _dispatch(self, params):
        api = params.get("api", "")
        method = params.get("method", "")
        p = self._parsed(params)

        if api == "SYNO.API.Auth":
            if method == "login":
                if p.get("passwd") == "secret":
                    STATE["logged_in"] = True
                    return {"success": True, "data": {"sid": SID, "did": "mockdid123"}}
                return {"success": False, "error": {"code": 400}}
            return {"success": True, "data": {}}

        if api == "SYNO.API.Info":
            return {"success": True, "data": api_info()}

        if params.get("_sid") != SID:
            return {"success": False, "error": {"code": 106}}

        if api == "SYNO.Core.System" and method == "info":
            if p.get("type") == "network":
                return {"success": True, "data": {"interfaces": [
                    {"name": "eth0", "ip": "192.168.1.50", "speed": 1000, "mac": "00:11:32:AA:BB:CC", "status": "up"}
                ], "dns": "223.5.5.5"}}
            return {"success": True, "data": system_info()}
        if api == "SYNO.Core.System.Utilization":
            return {"success": True, "data": utilization()}
        if api == "SYNO.Storage.CGI.Storage":
            return {"success": True, "data": storage()}
        if api == "SYNO.FileStation.List" and method == "list_share":
            return {"success": True, "data": {"shares": SHARES, "total": len(SHARES)}}
        if api == "SYNO.FileStation.List" and method == "list":
            path = p.get("folder_path", "/")
            return {"success": True, "data": {"files": FILES.get(path, []), "total": len(FILES.get(path, []))}}
        if api == "SYNO.FileStation.CreateFolder":
            return {"success": True, "data": {"folders": []}}
        if api == "SYNO.FileStation.Rename":
            return {"success": True, "data": {}}
        if api == "SYNO.FileStation.Delete":
            return {"success": True, "data": {}}
        if api == "SYNO.DownloadStation.Task" and method == "list":
            return {"success": True, "data": {"tasks": TASKS}}
        if api == "SYNO.DownloadStation.Task":
            return {"success": True, "data": {}}
        if api == "SYNO.Core.Package" and method == "list":
            return {"success": True, "data": {"packages": PACKAGES}}
        if api == "SYNO.Core.Package.Control":
            return {"success": True, "data": {}}
        if api == "SYNO.Core.User":
            return {"success": True, "data": {"users": [
                {"name": "admin", "description": "系统管理员", "groups": ["administrators"]},
                {"name": "guest", "description": "访客", "groups": ["guest"], "disabled": True},
            ]}}
        if api == "SYNO.Core.SyslogClient.Log":
            return {"success": True, "data": {"logs": [
                {"who": "admin", "descr": "通过 DSM 助手登录", "time": "2025-11-21 12:00:00", "logged_from": "192.168.1.2"}
            ]}}
        if api == "SYNO.Core.TaskScheduler":
            return {"success": True, "data": {"tasks": [
                {"id": "1", "name": "每日备份", "next_trigger_time": "2025-11-22 02:00", "enabled": True}
            ]}}
        if api == "SYNO.Core.Terminal":
            return {"success": True, "data": {"enable_ssh": True}}
        return {"success": False, "error": {"code": 102}}

    def do_GET(self):
        parsed = urlparse(self.path)
        params = {k: v[0] for k, v in parse_qs(parsed.query, keep_blank_values=True).items()}
        self._send(self._dispatch(params))

    def do_POST(self):
        if self.path.startswith("/webapi/auth.cgi") or self.path.startswith("/webapi/entry.cgi") or self.path.startswith("/webapi/query.cgi"):
            params = self._form()
            self._send(self._dispatch(params))
            return
        self._send({"success": False, "error": {"code": 404}}, 404)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5080
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"mock DSM listening on http://0.0.0.0:{port}", flush=True)
    server.serve_forever()
