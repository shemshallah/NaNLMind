# Koyeb training-delta merge, NANNET, Clocked, router and head-cortex service.
# One public service, multiple loopback workers. It never holds the 2 GiB map.
FROM debian:bookworm-slim AS native

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .
RUN make -j2
RUN mkdir -p /state \
 && ./build/nanlm-universal logic-train 8 16 /state/hermes-universe.nmg

FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir cryptography 'clocked-sdk==0.7.0'
COPY runner/training_merge.py /app/training_merge.py
COPY runner/hermes_router_delegate.py /app/runner/hermes_router_delegate.py
COPY runner/head_cortex_service.py /app/head_cortex_service.py
COPY runner/nannet_router /app/nannet_router
COPY runner/nannet_clocked /app/nannet_clocked
COPY deploy/training_merge/start_portal.sh /app/start_portal.sh
COPY nanlmind_nannet /app/nanlmind_nannet
COPY --from=native /src/build/nanlm-universal /app/nanlm-universal
COPY --from=native /state/hermes-universe.nmg /app/state/hermes-universe.nmg
ENV PYTHONUNBUFFERED=1 \
    NANLM_NATIVE_BINARY=/app/nanlm-universal \
    NANLM_HEAD_STATE=/app/state/hermes-universe.nmg \
    NANLM_HEAD_CORTEX_HOST=127.0.0.1 \
    NANLM_HEAD_CORTEX_PORT=18083 \
    NANLM_HEAD_CANDIDATE_DIR=/data/head-candidates
VOLUME ["/data"]
EXPOSE 8080
RUN chmod 0755 /app/start_portal.sh /app/nanlm-universal \
 && chmod 0644 /app/state/hermes-universe.nmg
CMD ["/app/start_portal.sh"]
