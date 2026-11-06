# Koyeb training-delta merge service. It never holds the 2 GiB bootstrap map.
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir cryptography
COPY runner/training_merge.py /app/training_merge.py
COPY runner/nannet_router /app/nannet_router
COPY deploy/training_merge/start_portal.sh /app/start_portal.sh
COPY nanlmind_nannet /app/nanlmind_nannet
ENV PYTHONUNBUFFERED=1
VOLUME ["/data"]
EXPOSE 8080
RUN chmod 0755 /app/start_portal.sh
CMD ["/app/start_portal.sh"]
