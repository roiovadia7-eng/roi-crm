import http.server, socketserver, os, json, urllib.request, urllib.parse

SUPABASE_URL = os.environ.get('SUPABASE_URL', 'https://gruaauwpicdklfmmmnjw.supabase.co')
SUPABASE_KEY = os.environ.get('SUPABASE_ANON_KEY', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdydWFhdXdwaWNka2xmbW1tbmp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3MjA3NjcsImV4cCI6MjA5MTI5Njc2N30.Odj6iPCaBwvxKsy4osIYxrzN_kBXnrsVDuVWYgHsjj0')

ALLOWED_TABLES = {'leads','deals','clients','payments','products','meetings','tasks',
                  'notes','record_tasks','record_history','files','users',
                  'audit_log','user_preferences','login_attempts','otp_codes'}
ALLOWED_RPC = {'get_leads_decrypted','get_deals_decrypted','get_clients_decrypted','send_whatsapp_otp'}

class CRMHandler(http.server.SimpleHTTPRequestHandler):

    def _read_body(self):
        length = int(self.headers.get('Content-Length', 0))
        return self.rfile.read(length) if length else b''

    def _require_auth(self):
        """Return True if auth token present, else send 401 and return False."""
        auth = self.headers.get('Authorization')
        if not auth or not auth.startswith('Bearer ') or len(auth) < 20:
            self._send_error(401, 'Authentication required')
            return False
        return True

    def _proxy(self, method, path, body=None):
        headers = {
            'apikey': SUPABASE_KEY,
            'Content-Type': 'application/json',
        }
        # Forward user's auth token if present; otherwise use anon key
        auth = self.headers.get('Authorization')
        headers['Authorization'] = auth if auth else f'Bearer {SUPABASE_KEY}'

        # Upsert needs Prefer header
        if method == 'POST' and '/rpc/' not in path:
            headers['Prefer'] = 'resolution=merge-duplicates,return=minimal'
        if method == 'PATCH':
            headers['Prefer'] = 'return=minimal'

        url = SUPABASE_URL + path
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req) as resp:
                data = resp.read()
                self._send(resp.status, data)
        except urllib.error.HTTPError as e:
            data = e.read()
            self._send(e.code, data)

    def _send(self, code, body=b''):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self._send(code, body)

    def _send_error(self, code, msg):
        self._send_json(code, {'error': msg})

    # ---------- GET ----------
    def do_GET(self):
        if self.path.startswith('/api/'):
            self._handle_api_get()
            return
        # Serve the CRM HTML at root and always bypass browser cache so edits
        # show up immediately without needing a manual hard-reload.
        if self.path in ('/', '/index.html'):
            self.path = '/ROI CRM.html'
        if self.path.endswith('.html'):
            try:
                fp = self.translate_path(self.path)
                with open(fp, 'rb') as f:
                    data = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
                self.send_header('Pragma', 'no-cache')
                self.send_header('Expires', '0')
                self.end_headers()
                self.wfile.write(data)
                return
            except FileNotFoundError:
                self._send_error(404, 'Not found')
                return
        super().do_GET()

    def _handle_api_get(self):
        parsed = urllib.parse.urlparse(self.path)
        parts = parsed.path.strip('/').split('/')  # ['api', ...]

        if len(parts) == 3 and parts[1] == 'auth' and parts[2] == 'session':
            # Validate token → GET /auth/v1/user
            self._proxy('GET', '/auth/v1/user')
            return

        if len(parts) == 3 and parts[1] == 'data':
            if not self._require_auth(): return
            table = parts[2]
            if table not in ALLOWED_TABLES:
                self._send_error(403, 'Table not allowed')
                return
            qs = '?' + parsed.query if parsed.query else '?select=*'
            self._proxy('GET', f'/rest/v1/{table}{qs}')
            return

        self._send_error(404, 'Not found')

    # ---------- POST ----------
    def do_POST(self):
        if not self.path.startswith('/api/'):
            self._send_error(404, 'Not found')
            return
        body = self._read_body()
        parsed = urllib.parse.urlparse(self.path)
        parts = parsed.path.strip('/').split('/')

        # /api/auth/login
        if len(parts) == 3 and parts[1] == 'auth' and parts[2] == 'login':
            self._proxy('POST', '/auth/v1/token?grant_type=password', body)
            return

        # /api/auth/logout
        if len(parts) == 3 and parts[1] == 'auth' and parts[2] == 'logout':
            self._proxy('POST', '/auth/v1/logout', body)
            return

        # /api/auth/refresh
        if len(parts) == 3 and parts[1] == 'auth' and parts[2] == 'refresh':
            self._proxy('POST', '/auth/v1/token?grant_type=refresh_token', body)
            return

        # /api/rpc/{fn}
        if len(parts) == 3 and parts[1] == 'rpc':
            if not self._require_auth(): return
            fn = parts[2]
            if fn not in ALLOWED_RPC:
                self._send_error(403, 'RPC not allowed')
                return
            self._proxy('POST', f'/rest/v1/rpc/{fn}', body)
            return

        # /api/data/{table}
        if len(parts) == 3 and parts[1] == 'data':
            if not self._require_auth(): return
            table = parts[2]
            if table not in ALLOWED_TABLES:
                self._send_error(403, 'Table not allowed')
                return
            self._proxy('POST', f'/rest/v1/{table}', body)
            return

        self._send_error(404, 'Not found')

    # ---------- DELETE ----------
    def do_DELETE(self):
        if not self.path.startswith('/api/'):
            self._send_error(404, 'Not found')
            return
        if not self._require_auth(): return
        parsed = urllib.parse.urlparse(self.path)
        parts = parsed.path.strip('/').split('/')

        if len(parts) == 3 and parts[1] == 'data':
            table = parts[2]
            if table not in ALLOWED_TABLES:
                self._send_error(403, 'Table not allowed')
                return
            qs = '?' + parsed.query if parsed.query else ''
            self._proxy('DELETE', f'/rest/v1/{table}{qs}')
            return

        self._send_error(404, 'Not found')

    # ---------- PATCH ----------
    def do_PATCH(self):
        if not self.path.startswith('/api/'):
            self._send_error(404, 'Not found')
            return
        if not self._require_auth(): return
        body = self._read_body()
        parsed = urllib.parse.urlparse(self.path)
        parts = parsed.path.strip('/').split('/')

        if len(parts) == 3 and parts[1] == 'data':
            table = parts[2]
            if table not in ALLOWED_TABLES:
                self._send_error(403, 'Table not allowed')
                return
            qs = '?' + parsed.query if parsed.query else ''
            self._proxy('PATCH', f'/rest/v1/{table}{qs}', body)
            return

        self._send_error(404, 'Not found')

    # Suppress default logging noise
    def log_message(self, format, *args):
        if '/api/' in (args[0] if args else ''):
            print(f"API: {args[0]}", flush=True)


class ThreadedServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True

port = int(os.environ.get("PORT", 8080))
print(f"ROI CRM server on port {port}", flush=True)
with ThreadedServer(("0.0.0.0", port), CRMHandler) as h:
    h.serve_forever()
