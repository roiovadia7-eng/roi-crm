FROM python:3.11-slim
WORKDIR /app
COPY . .
ENTRYPOINT ["sh", "-c", "python3 -m http.server ${PORT:-8080} --bind 0.0.0.0"]
