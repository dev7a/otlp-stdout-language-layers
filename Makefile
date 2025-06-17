# Build layers that add the otlp-stdout-span-exporter:
# - Full layers: Clone upstream and modify to add OTLP stdout support
# - Overlay layers: Thin layers that extend existing upstream layers

AWS_REGION            ?= us-east-1

# Upstream repository and version
UPSTREAM_REPO         ?= https://github.com/open-telemetry/opentelemetry-lambda.git
UPSTREAM_BRANCH       ?= main

# Upstream instrumentation layer ARNs (used for overlay layers)
PY_BASE_LAYER_ARN     ?= arn:aws:lambda:$(AWS_REGION):184161586896:layer:opentelemetry-python-0_14_0:1
NODE_BASE_LAYER_ARN   ?= arn:aws:lambda:$(AWS_REGION):184161586896:layer:opentelemetry-nodejs-0_14_0:1

# Version of the exporter package to embed. "latest" keeps us current.
EXPORTER_VERSION      ?= latest

# Extract the version fragment (e.g. 0_14_0) from each ARN for naming overlay layers.
PY_UPSTREAM_VERSION   := $(shell echo $(PY_BASE_LAYER_ARN)   | sed -E 's/.*python-([^:]*):.*/\1/')
NODE_UPSTREAM_VERSION := $(shell echo $(NODE_BASE_LAYER_ARN) | sed -E 's/.*nodejs-([^:]*):.*/\1/')

# For full layers, use branch name as version
UPSTREAM_VERSION      := $(shell echo $(UPSTREAM_BRANCH) | tr '/' '_')

DIST_DIR = dist
CLONE_DIR = /tmp/upstream-clone

.DEFAULT_GOAL := help

.PHONY: help build build-python-layer build-node-layer build-python-layer-overlay build-node-layer-overlay \
        clean clean-dist clean-clone publish-python-layer publish-node-layer publish show-arns \
        clone-upstream

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}'

# Build both full layers
build: build-python-layer build-node-layer ## Build both Python and Node.js full layers
	@echo "✅ Both full layers built successfully!"

# Full layer builds (clone upstream and modify)
clone-upstream: ## Clone the upstream opentelemetry-lambda repository
	@echo "Cloning upstream repository ($(UPSTREAM_BRANCH)) …"
	@rm -rf $(CLONE_DIR)
	@git clone --depth 1 --branch $(UPSTREAM_BRANCH) $(UPSTREAM_REPO) $(CLONE_DIR)

build-python-layer: clone-upstream ## Build the Python full layer from source
	@echo "Building Python full layer ($(UPSTREAM_VERSION)) …"
	@mkdir -p $(DIST_DIR)
	# Follow the upstream build steps manually
	@mkdir -p $(DIST_DIR)/python-layer-temp/python
	@mkdir -p $(DIST_DIR)/python-layer-temp/tmp
	# Install requirements to python directory
	@python3 -m pip install -r $(CLONE_DIR)/python/src/otel/otel_sdk/requirements.txt -t $(DIST_DIR)/python-layer-temp/python
	@python3 -m pip install -r $(CLONE_DIR)/python/src/otel/otel_sdk/nodeps-requirements.txt -t $(DIST_DIR)/python-layer-temp/tmp --no-deps
	# Add our exporter to the python directory
	@python3 -m pip install otlp-stdout-span-exporter$(if $(filter-out latest,$(EXPORTER_VERSION)),==$(EXPORTER_VERSION)) -t $(DIST_DIR)/python-layer-temp/python
	# Merge tmp into python
	@cp -r $(DIST_DIR)/python-layer-temp/tmp/* $(DIST_DIR)/python-layer-temp/python/
	@rm -rf $(DIST_DIR)/python-layer-temp/tmp
	# Copy otel_sdk files
	@cp -r $(CLONE_DIR)/python/src/otel/otel_sdk/* $(DIST_DIR)/python-layer-temp/python/
	# Copy otel-instrument to root level (like upstream)
	@cp $(DIST_DIR)/python-layer-temp/python/otel-instrument $(DIST_DIR)/python-layer-temp/
	# Set permissions
	@if [ -f $(DIST_DIR)/python-layer-temp/otel-instrument ]; then chmod 755 $(DIST_DIR)/python-layer-temp/otel-instrument; fi
	@if [ -f $(DIST_DIR)/python-layer-temp/otel-handler ]; then chmod 755 $(DIST_DIR)/python-layer-temp/otel-handler; fi
	@if [ -f $(DIST_DIR)/python-layer-temp/python/otel-instrument ]; then chmod 755 $(DIST_DIR)/python-layer-temp/python/otel-instrument; fi
	@if [ -f $(DIST_DIR)/python-layer-temp/python/otel-handler ]; then chmod 755 $(DIST_DIR)/python-layer-temp/python/otel-handler; fi
	# Remove unwanted packages
	@rm -rf $(DIST_DIR)/python-layer-temp/python/boto*
	@rm -rf $(DIST_DIR)/python-layer-temp/python/urllib3*
	# Package the layer
	@cd $(DIST_DIR)/python-layer-temp && zip -qr ../otlp-stdout-python-$(UPSTREAM_VERSION).zip .
	@rm -rf $(DIST_DIR)/python-layer-temp

build-node-layer: clone-upstream ## Build the Node.js full layer from source
	@echo "Building Node full layer ($(UPSTREAM_VERSION)) …"
	@mkdir -p $(DIST_DIR)
	# Apply our patch to add configureExporters support
	@cd $(CLONE_DIR) && git apply --ignore-whitespace $(PWD)/nodejs/wrapper-override.patch
	# Install root dev dependencies (includes rimraf, etc.)
	@cd $(CLONE_DIR)/nodejs && npm install
	# Add our exporter to package.json dependencies
	@cd $(CLONE_DIR)/nodejs/packages/layer && npm install @dev7a/otlp-stdout-span-exporter$(if $(filter-out latest,$(EXPORTER_VERSION)),@$(EXPORTER_VERSION))
	# Copy our patch and otel-handler override
	@cp $(PWD)/nodejs/patch-full-layer.mjs $(CLONE_DIR)/nodejs/packages/layer/src/patch-full-layer.mjs
	@cp $(PWD)/nodejs/otel-handler $(CLONE_DIR)/nodejs/packages/layer/scripts/otel-handler
	# Build the layer (but not package yet)
	@cd $(CLONE_DIR)/nodejs/packages/layer && npm run clean && npm run compile && npm run install-externals
	# Install our exporter package in the build workspace
	@cd $(CLONE_DIR)/nodejs/packages/layer/build/workspace && npm install @dev7a/otlp-stdout-span-exporter$(if $(filter-out latest,$(EXPORTER_VERSION)),@$(EXPORTER_VERSION)) --production
	# Now package the layer with our exporter included
	@cd $(CLONE_DIR)/nodejs/packages/layer && npm run package
	# Copy the built layer
	@cp $(CLONE_DIR)/nodejs/packages/layer/build/layer.zip $(DIST_DIR)/otlp-stdout-node-$(UPSTREAM_VERSION).zip

# Overlay layer builds (original approach)
build-python-layer-overlay: ## Build the Python overlay layer (requires Docker)
	@echo "Building Python overlay layer (upstream $(PY_UPSTREAM_VERSION)) …"
	@mkdir -p $(DIST_DIR)
	docker build -f python/Dockerfile \
	    --build-arg EXPORTER_VERSION=$(EXPORTER_VERSION) \
	    --output type=local,dest=$(DIST_DIR) .
	mv $(DIST_DIR)/layer.zip $(DIST_DIR)/otlp-stdout-python-overlay-$(PY_UPSTREAM_VERSION).zip

build-node-layer-overlay: ## Build the Node.js overlay layer (requires Docker, not yet functional)
	@echo "Building Node overlay layer (upstream $(NODE_UPSTREAM_VERSION)) …"
	@mkdir -p $(DIST_DIR)
	docker build -f nodejs/Dockerfile \
	    --build-arg EXPORTER_VERSION=$(EXPORTER_VERSION) \
	    --output type=local,dest=$(DIST_DIR) .
	mv $(DIST_DIR)/layer.zip $(DIST_DIR)/otlp-stdout-node-overlay-$(NODE_UPSTREAM_VERSION).zip

publish-python-layer: build-python-layer ## Build and publish the Python full layer to AWS
	@echo "Publishing Python full layer to AWS account in $(AWS_REGION) …"
	@LAYER_ARN=$$(aws lambda publish-layer-version \
	    --layer-name "otlp-stdout-python-$(UPSTREAM_VERSION)" \
	    --description "OTLP Stdout exporter for OpenTelemetry Python ($(UPSTREAM_VERSION))" \
	    --zip-file fileb://$(DIST_DIR)/otlp-stdout-python-$(UPSTREAM_VERSION).zip \
	    --compatible-runtimes python3.8 python3.9 python3.10 python3.11 python3.12 python3.13 \
	    --region $(AWS_REGION) \
	    --query 'LayerVersionArn' --output text) && \
	echo "✅ Python layer published: $$LAYER_ARN"

publish-node-layer: build-node-layer ## Build and publish the Node.js full layer to AWS
	@echo "Publishing Node full layer to AWS account in $(AWS_REGION) …"
	@LAYER_ARN=$$(aws lambda publish-layer-version \
	    --layer-name "otlp-stdout-node-$(UPSTREAM_VERSION)" \
	    --description "OTLP Stdout exporter for OpenTelemetry Node.js ($(UPSTREAM_VERSION))" \
	    --zip-file fileb://$(DIST_DIR)/otlp-stdout-node-$(UPSTREAM_VERSION).zip \
	    --compatible-runtimes nodejs18.x nodejs20.x nodejs22.x \
	    --region $(AWS_REGION) \
	    --query 'LayerVersionArn' --output text) && \
	echo "✅ Node layer published: $$LAYER_ARN"

publish: publish-python-layer publish-node-layer ## Build and publish both full layers to AWS
	@echo ""
	@echo "🎉 Both full layers published successfully!"
	@echo ""
	@echo "To use these layers in your Lambda functions:"
	@echo "1. Add the published layer to your function"
	@echo "2. Set AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument (Python) or /opt/otel-handler (Node)"
	@echo "3. Set OTEL_TRACES_EXPORTER=otlpstdout"

show-arns: ## Show the ARNs of the latest published layers
	@echo "Current layer ARNs in $(AWS_REGION):"
	@echo ""
	@echo "Python full layer:"
	@aws lambda get-layer-version \
	    --layer-name "otlp-stdout-python-$(UPSTREAM_VERSION)" \
	    --version-number $$(aws lambda list-layer-versions \
	        --layer-name "otlp-stdout-python-$(UPSTREAM_VERSION)" \
	        --query 'LayerVersions[0].Version' --output text) \
	    --query 'LayerVersionArn' --output text 2>/dev/null || echo "  (not published yet)"
	@echo ""
	@echo "Node full layer:"
	@aws lambda get-layer-version \
	    --layer-name "otlp-stdout-node-$(UPSTREAM_VERSION)" \
	    --version-number $$(aws lambda list-layer-versions \
	        --layer-name "otlp-stdout-node-$(UPSTREAM_VERSION)" \
	        --query 'LayerVersions[0].Version' --output text) \
	    --query 'LayerVersionArn' --output text 2>/dev/null || echo "  (not published yet)"

clean: ## Remove all build artifacts and the cloned repository
	@echo "This will remove ALL build artifacts and cloned repositories:"
	@echo "  - $(DIST_DIR)/"
	@echo "  - $(CLONE_DIR)/"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Removing all artifacts..."; \
		rm -rf $(DIST_DIR) $(CLONE_DIR); \
	else \
		echo "Cancelled."; \
	fi

clean-dist: ## Remove build artifacts from the dist/ directory
	@echo "This will remove all built artifacts in $(DIST_DIR)/"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Removing $(DIST_DIR)/..."; \
		rm -rf $(DIST_DIR); \
	else \
		echo "Cancelled."; \
	fi

clean-clone: ## Remove the cloned upstream repository
	@echo "This will remove the cloned upstream repository in $(CLONE_DIR)/"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Removing $(CLONE_DIR)/..."; \
		rm -rf $(CLONE_DIR); \
	else \
		echo "Cancelled."; \
	fi 