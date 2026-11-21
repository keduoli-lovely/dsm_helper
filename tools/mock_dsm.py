"""本地伪 DSM WebAPI，用于在没有真实群晖时验证登录与各页面数据解析。

用法: python tools/mock_dsm.py [port]
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

SID = "MOCKSID123"
HERE = os.path.dirname(os.path.abspath(__file__))
STATE = {"logged_in": False}

USERS = [
    {"name": "admin", "description": "系统管理员", "email": "admin@example.com", "groups": ["administrators"]},
    {"name": "guest", "description": "访客", "email": "", "groups": ["guest"], "disabled": True},
]

LOGS = [
    {"who": "admin", "descr": "通过 DSM 助手登录", "time": "2025-11-21 12:00:00", "logged_from": "192.168.1.2"},
    {"who": "system", "descr": "存储空间 1 的 SMART 检测完成，状态正常", "time": "2025-11-21 03:00:02", "logged_from": ""},
    {"who": "DownloadStation", "descr": "下载任务「三体.S01E05」已完成", "time": "2025-11-20 22:41:07", "logged_from": ""},
]

LINKS = [
    {"id": "link_1", "url": "https://mock-nas.example.com/sharing/abc123", "expire_date": "永久", "link_owner": "admin"},
]

PHOTOS = [
    {
        "id": 1000 + i,
        "filename": f"IMG_{2000 + i}.jpg",
        "time": int(time.time()) - i * 86400 * 2,
        "additional": {"thumbnail": {"cache_key": f"{1000 + i}_123", "sm": "ready", "m": "ready", "xl": "ready"}},
    }
    for i in range(18)
]


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
            "SYNO.FileStation.Sharing",
            "SYNO.DownloadStation.Task",
            "SYNO.Core.Package",
            "SYNO.Core.Package.Control",
            "SYNO.Core.User",
            "SYNO.Core.SyslogClient.Log",
            "SYNO.Core.TaskScheduler",
            "SYNO.Core.Terminal",
            "SYNO.Foto.Browse.Item",
            "SYNO.Foto.Thumbnail",
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
    "/photo/2025": [
        {"name": "IMG_2031.jpg", "path": "/photo/2025/IMG_2031.jpg", "isdir": False,
         "additional": {"size": 4200000, "time": {"mtime": int(time.time())}}},
    ],
    "/home": [],
}

TASKS = [
    {"id": "dbid_1", "title": "Mock.Task.2160p.mkv", "status": "downloading", "size": 8000000000,
     "additional": {"transfer": {"size_downloaded": 3200000000, "speed_download": 5400000}, "detail": {"destination": "/video"}}},
    {"id": "dbid_2", "title": "Mock.Finished.iso", "status": "finished", "size": 2000000000,
     "additional": {"transfer": {"size_downloaded": 2000000000, "speed_download": 0}, "detail": {"destination": "/video"}}},
]

PACKAGES = [
    {"id": "SynologyPhotos", "name": "Synology Photos", "version": "1.7.1-0819", "status": "running", "startable": True, "description": "智能照片管理"},
    {"id": "DownloadStation", "name": "Download Station", "version": "4.0.6-3829", "status": "running", "startable": True, "description": "下载中心"},
    {"id": "Docker", "name": "Container Manager", "version": "24.0.2-1535", "status": "running", "startable": True, "description": "容器管理"},
    {"id": "SynologyDrive", "name": "Synology Drive Server", "version": "3.5.1-26102", "status": "running", "startable": True, "description": "私有云盘"},
    {"id": "PlexMediaServer", "name": "Plex Media Server", "version": "1.41.3", "status": "running", "startable": True, "description": "影音服务"},
    {"id": "Virtualization", "name": "Virtual Machine Manager", "version": "2.6.5-12202", "status": "stopped", "startable": True, "description": "虚拟机"},
    {"id": "MariaDB10", "name": "MariaDB 10", "version": "10.1.48-0120", "status": "stopped", "startable": True, "description": "数据库"},
    {"id": "LogCenter", "name": "Log Center", "version": "1.4.3-0150", "status": "running", "startable": False, "description": "系统日志中心"},
    {"id": "SynologyApplicationService", "name": "Synology Application Service", "version": "1.7.6-0831", "status": "running", "startable": False, "description": "系统基础服务"},
]


def storage():
    return {
        "volumes": [
            {"id": "volume_1", "display_name": "存储空间 1", "status": "normal", "fs_type": "btrfs", "raid_type": "SHR",
             "size": {"total": 4000000000000, "used": 2400000000000}}
        ],
        "disks": [
            {"id": "sata1", "model": "WD40EFRX", "size_total": 4000787030016, "status": "normal", "temp": 35},
            {"id": "sata2", "model": "WD40EFRX", "size_total": 4000787030016, "status": "normal"},
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

    def _send_png(self, filename):
        path = os.path.join(HERE, filename)
        with open(path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
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
        if api == "SYNO.FileStation.Sharing":
            if method == "create":
                path = p.get("path") or []
                link = {"id": f"link_{len(LINKS) + 1}", "url": f"https://mock-nas.example.com/sharing/link{len(LINKS) + 1}",
                        "expire_date": "永久", "link_owner": "admin", "path": path}
                LINKS.append(link)
                return {"success": True, "data": {"links": [link]}}
            if method == "list":
                return {"success": True, "data": {"links": LINKS, "total": len(LINKS)}}
            if method == "delete":
                ids = p.get("id") or []
                if isinstance(ids, str):
                    ids = [ids]
                for link in list(LINKS):
                    if link["id"] in ids:
                        LINKS.remove(link)
                return {"success": True, "data": {}}
        if api == "SYNO.DownloadStation.Task" and method == "list":
            return {"success": True, "data": {"tasks": TASKS}}
        if api == "SYNO.DownloadStation.Task":
            return {"success": True, "data": {}}
        if api == "SYNO.Core.Package" and method == "list":
            return {"success": True, "data": {"packages": PACKAGES}}
        if api == "SYNO.Core.Package.Control":
            pid = p.get("id")
            for pkg in PACKAGES:
                if pkg["id"] == pid:
                    pkg["status"] = "running" if method == "start" else "stopped"
            return {"success": True, "data": {}}
        if api == "SYNO.Core.User":
            if method == "list":
                return {"success": True, "data": {"users": USERS}}
            if method == "get":
                name = p.get("name")
                for user in USERS:
                    if user["name"] == name:
                        return {"success": True, "data": {"name": name, "email": user.get("email", ""),
                                                          "description": user.get("description", ""),
                                                          "avatar": "/webman/mock/avatar.png"}}
                return {"success": False, "error": {"code": 102}}
            if method == "set":
                name = p.get("name")
                for user in USERS:
                    if user["name"] == name:
                        if "description" in p:
                            user["description"] = p["description"]
                        if "email" in p:
                            user["email"] = p["email"]
                return {"success": True, "data": {}}
        if api == "SYNO.Core.SyslogClient.Log":
            if method == "list":
                return {"success": True, "data": {"logs": LOGS}}
            if method == "clear":
                LOGS.clear()
                return {"success": True, "data": {}}
        if api == "SYNO.Core.TaskScheduler":
            return {"success": True, "data": {"tasks": [
                {"id": "1", "name": "每日备份", "next_trigger_time": "2025-11-22 02:00", "enabled": True}
            ]}}
        if api == "SYNO.Core.Terminal":
            return {"success": True, "data": {"enable_ssh": True, "ssh_port": 22}}
        if api == "SYNO.Foto.Browse.Item" and method == "list":
            offset = int(p.get("offset", 0) or 0)
            limit = int(p.get("limit", 100) or 100)
            items = PHOTOS[offset:offset + limit]
            return {"success": True, "data": {"list": items, "total": len(PHOTOS)}}
        if api == "SYNO.Foto.Thumbnail":
            pid = int(p.get("id", 0) or 0)
            return {"success": True, "data": {"_image": "photo", "index": pid % 6}}
        if api == "SYNO.FileStation.Thumb":
            path = p.get("path", "photo")
            if isinstance(path, list):
                path = path[0] if path else "photo"
            return {"success": True, "data": {"_image": "photo", "index": abs(hash(path)) % 6}}
        return {"success": False, "error": {"code": 102}}

    def _send_json_bytes(self, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _immich_asset(self, path):
        if path.startswith("/api/assets/"):
            asset_id = path.split("/")[3]
            idx = abs(hash(asset_id)) % 6
            self._send_png(f"mock_photo_{idx}.png")
            return True
        return False

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/server/about":
            self._send_json_bytes({"version": "v1.132.0", "source": "mock"})
            return
        if self._immich_asset(parsed.path):
            return
        if parsed.path.startswith("/webman/3rdparty/"):
            self._send_png("mock_pkg_icon.png")
            return
        if parsed.path.startswith("/webman/mock/"):
            self._send_png("mock_avatar.png")
            return
        params = {k: v[0] for k, v in parse_qs(parsed.query, keep_blank_values=True).items()}
        if params.get("api") == "SYNO.Foto.Thumbnail":
            pid = int(params.get("id", 0) or 0)
            self._send_png(f"mock_photo_{pid % 6}.png")
            return
        if params.get("api") == "SYNO.FileStation.Thumb":
            path = params.get("path", "photo")
            self._send_png(f"mock_photo_{abs(hash(path)) % 6}.png")
            return
        self._send(self._dispatch(params))

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/search/metadata":
            length = int(self.headers.get("Content-Length", 0))
            self.rfile.read(length)
            items = [
                {
                    "id": f"asset-{i}",
                    "type": "IMAGE",
                    "originalFileName": f"IMG_{3000 + i}.jpg",
                    "fileCreatedAt": f"2025-{((i % 6) + 6):02d}-{((i % 27) + 1):02d}T10:00:00.000Z",
                }
                for i in range(12)
            ]
            self._send_json_bytes({"albums": {"total": 0, "count": 0, "items": []},
                                   "assets": {"total": len(items), "count": len(items), "items": items, "nextPage": None}})
            return
        if self._immich_asset(parsed.path):
            return
        if self.path.startswith("/webapi/"):
            params = self._form()
            if params.get("api") == "SYNO.Foto.Thumbnail":
                pid = int(params.get("id", 0) or 0)
                self._send_png(f"mock_photo_{pid % 6}.png")
                return
            if params.get("api") == "SYNO.FileStation.Thumb":
                path = params.get("path", "photo")
                self._send_png(f"mock_photo_{abs(hash(path)) % 6}.png")
                return
            self._send(self._dispatch(params))
            return
        self._send({"success": False, "error": {"code": 404}}, 404)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 5080
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"mock DSM listening on http://0.0.0.0:{port}", flush=True)
    server.serve_forever()
