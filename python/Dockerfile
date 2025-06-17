# Build stage
FROM public.ecr.aws/sam/build-python3.13 AS builder

ARG EXPORTER_VERSION=latest

# 1. Install the exporter into /layer/python
RUN mkdir -p /layer/python && \
    if [ "${EXPORTER_VERSION}" = "latest" ]; then \
        python3 -m pip install --no-cache-dir "otlp-stdout-span-exporter" -t /layer/python; \
    else \
        python3 -m pip install --no-cache-dir "otlp-stdout-span-exporter==${EXPORTER_VERSION}" -t /layer/python; \
    fi

# 2. Package the layer
WORKDIR /layer
RUN zip -qr layer.zip .

# Export stage – copy the zip so that `docker build --output` can retrieve it
FROM scratch AS export
COPY --from=builder /layer/layer.zip /layer.zip 