# Build stage
FROM public.ecr.aws/sam/build-nodejs20.x AS builder

ARG EXPORTER_VERSION=latest

# 1. Prepare layer folder structure to match upstream
RUN mkdir -p /layer/node_modules
WORKDIR /layer

# 2. Install exporter package directly into node_modules (no package.json)
RUN if [ "${EXPORTER_VERSION}" = "latest" ]; then \
        npm install --production --no-package-lock --no-save "@dev7a/otlp-stdout-span-exporter"; \
    else \
        npm install --production --no-package-lock --no-save "@dev7a/otlp-stdout-span-exporter@${EXPORTER_VERSION}"; \
    fi

# 3. Copy overlay scripts
COPY nodejs/patch.mjs /layer/patch.mjs
COPY nodejs/otel-handler /layer/otel-handler
RUN chmod +x /layer/otel-handler

# 4. Package the layer
RUN zip -qr layer.zip .

# Export stage
FROM scratch AS export
COPY --from=builder /layer/layer.zip /layer.zip 