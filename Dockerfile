FROM python:3.11-slim
WORKDIR /app
COPY . .
CMD ["sh", "-c", "python3 -m http.server $PORT --bind 0.0.0.0"]
