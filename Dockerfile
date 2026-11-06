FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/deeprepo \
    NANLM_DATA_DIR=/data/nannet

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/deeprepo \
 && git -C /opt/deeprepo init \
 && git -C /opt/deeprepo remote add origin https://github.com/shemshallah/deeprepo.git \
 && git -C /opt/deeprepo fetch --depth 1 origin 4c6bd84d1b13498ff1b8107a024725bc5c6a389a \
 && git -C /opt/deeprepo checkout --detach FETCH_HEAD \
 && pip install --no-cache-dir -r /opt/deeprepo/requirements-core.txt

WORKDIR /app
COPY integrations/nannet/ /app/
EXPOSE 8000
CMD ["python", "server.py"]
