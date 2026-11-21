# Relais du mode réseau : image minimale, utilisateur sans droits, aucun volume.
FROM python:3.12-slim
RUN pip install --no-cache-dir websockets==15.0.1 && useradd -r -u 10001 -M -s /usr/sbin/nologin relais
WORKDIR /app
COPY salons.py relais.py /app/
USER 10001
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
EXPOSE 8790
CMD ["python", "/app/relais.py", "--hote", "0.0.0.0", "--port", "8790"]
