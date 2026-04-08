import http.server, socketserver, os
port = int(os.environ.get("PORT", 8080))
Handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(("0.0.0.0", port), Handler) as h:
    print(f"Serving on port {port}", flush=True)
    h.serve_forever()
