FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py entrypoint.sh ./
RUN chmod +x entrypoint.sh

ENV GIT_DATA_DIR=/data/teleport.git \
    HOST=0.0.0.0 \
    PORT=8000

VOLUME ["/data"]

EXPOSE 8000

ENTRYPOINT ["./entrypoint.sh"]
