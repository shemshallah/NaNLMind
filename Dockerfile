FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/deeprepo \
    NANLM_DATA_DIR=/data/nannet

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 https://github.com/shemshallah/deeprepo.git /opt/deeprepo \
 && pip install --no-cache-dir -r /opt/deeprepo/requirements-core.txt

WORKDIR /app
COPY integrations/nannet/ /app/
EXPOSE 8000
CMD ["python", "server.py"]
