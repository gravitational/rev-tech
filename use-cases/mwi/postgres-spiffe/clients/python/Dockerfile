# Optional: a real pre-built image, for pushing to your own registry
# instead of the default self-compiling-in-ubuntu approach chart/templates/job.yaml
# uses (see chart/values.yaml's `selfCompile`). Build from this
# directory: `docker build -t <tag> .`
FROM python:3.12-slim

WORKDIR /app
COPY chart/app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY chart/app/transact.py .

USER 65534:65534
ENTRYPOINT ["python", "/app/transact.py"]
