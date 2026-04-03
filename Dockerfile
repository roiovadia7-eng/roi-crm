FROM python:3.11-slim
WORKDIR /app
COPY . .
RUN printf 'import http.server, socketserver, os\nport = int(os.environ.get("PORT", 8080))\nHandler = http.server.SimpleHTTPRequestHandler\nwith socketserver.TCPServer(("0.0.0.0", port), Handler) as h:\n    print(f"Serving on port {port}", flush=True)\n    h.serve_forever()\n' > serve.py
CMD ["python3", "-u", "serve.py"]
