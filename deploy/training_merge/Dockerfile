# Koyeb training-delta merge service. It never holds the 2 GiB bootstrap map.
FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir cryptography
COPY runner/training_merge.py /app/training_merge.py
COPY nanlmind_nannet /app/nanlmind_nannet
ENV PYTHONUNBUFFERED=1
VOLUME ["/data"]
EXPOSE 8080
CMD ["python", "/app/training_merge.py", "--root", "/data", "--port", "8080"]
