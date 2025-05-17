PHP_VERSION			:= 8.4.7
LAMBDA_RUNTIME		:= al2023
LAMBDA_ARCH			:= arm64

#------------------------------------------------------------------------

BUILD_DIR			:= build
WORK_DIR			:= $(BUILD_DIR)/work

# the final output target lambda layer runtime package to generate
PHP_VERSION_ARCH	:= $(PHP_VERSION)-$(LAMBDA_ARCH)
PHP_RUNTIME_NAME	:= php-$(PHP_VERSION_ARCH)-runtime
PHP_RUNTIME_PACKAGE	:= $(BUILD_DIR)/$(PHP_RUNTIME_NAME).zip

SOURCES				:= $(shell find src -type f)
TEST_SOURCES		:= $(shell find tests -type f)
SHELL				:= /bin/bash

UNAME_OS			:= $(shell uname -s)
ifeq ($(UNAME_OS),Darwin)
BASE64_DECODE		:= base64 --decode
else
BASE64_DECODE		:= base64 -d
endif

AWS_ACCOUNT_ID		?= $(shell aws sts get-caller-identity | jq -r .Account)
AWS_DEFAULT_REGION	?= $(shell aws configure get region)

LAMBDA_LAYER_NAME	:= $(subst .,_,$(PHP_RUNTIME_NAME))
LAMBDA_TEST_NAME	:= $(LAMBDA_LAYER_NAME)-tests
LAMBDA_EXECUTE_ROLE	:= LambdaBasicExecute
LAMBDA_TEST_HANDLER	:= phpinfo.lambdaHandler

TESTS_PACKAGE		:= $(BUILD_DIR)/tests.zip

TS_LAYER_PUBLISH			:= $(BUILD_DIR)/$(LAMBDA_LAYER_NAME)-publish.timestamp
TS_FUNCTION_CREATE			:= $(BUILD_DIR)/$(LAMBDA_TEST_NAME)-create.timestamp
TS_FUNCTION_URL_CREATE		:= $(BUILD_DIR)/$(LAMBDA_TEST_NAME)-create-url.timestamp
TS_FUNCTION_UPDATE_CONFIG	:= $(BUILD_DIR)/$(LAMBDA_TEST_NAME)-update-config.timestamp
TS_FUNCTION_UPDATE_CODE		:= $(BUILD_DIR)/$(LAMBDA_TEST_NAME)-update-code.timestamp
TS_FUNCTION_URL_PERMISSION	:= $(BUILD_DIR)/$(LAMBDA_TEST_NAME)-url-permission.timestamp

#------------------------------------------------------------------------

.DELETE_ON_ERROR:

default: $(TS_LAYER_PUBLISH)

# build the specified PHP version from source using Docker, extracting the compiled PHP binary and dependent libraries to our work directory
$(WORK_DIR)/php-runtime/bin/php: Dockerfile Makefile
	@rm -rf $(WORK_DIR) ; mkdir -p $(dir $@)
	docker build --build-arg LAMBDA_ARCH="$(LAMBDA_ARCH)" --build-arg LAMBDA_RUNTIME="$(LAMBDA_RUNTIME)" --build-arg PHP_VERSION="$(PHP_VERSION)" -t "aws-lambda-php-runtime:$(PHP_VERSION)-$(LAMBDA_ARCH)" -f $< .
	docker run -v $(PWD)/$(WORK_DIR):/mnt --rm --entrypoint cp "aws-lambda-php-runtime:$(PHP_VERSION)-$(LAMBDA_ARCH)" /root/php-runtime.zip /mnt
	cd $(WORK_DIR) ; unzip -o ./php-runtime.zip ; rm ./php-runtime.zip
	@touch $@

# copy our PHP runtime sources into the work directory, and create a zip file for the lambda layer
$(PHP_RUNTIME_PACKAGE): $(WORK_DIR)/php-runtime/bin/php $(SOURCES)
	cp -r src/* $(WORK_DIR)
	cd $(WORK_DIR) && zip -v -9 -r ../../$@ ./*

# publish runtime to layer
$(TS_LAYER_PUBLISH): $(PHP_RUNTIME_PACKAGE)
	aws lambda publish-layer-version --layer-name "$(LAMBDA_LAYER_NAME)" \
		--compatible-architectures "$(LAMBDA_ARCH)" --compatible-runtimes "provided.$(LAMBDA_RUNTIME)" \
		--description "PHP $(PHP_VERSION) ($(LAMBDA_ARCH)) Runtime for AWS Lambda" \
		--license-info "Built using scripts and sources developed by Cold Fusion, Inc. For version updates and license info, see: https://github.com/coldfusionjp/aws-lambda-php-runtime" \
		--zip-file fileb://$<
	@touch $@

# package test functions
$(TESTS_PACKAGE): $(TEST_SOURCES)
	@rm -f $@
	@mkdir -p $(dir $@)
	cd tests && zip -v -9 -r ../$@ ./*

# perform lambda function creation for testing
$(TS_FUNCTION_CREATE): $(TESTS_PACKAGE)
	aws lambda get-function --function-name "$(LAMBDA_TEST_NAME)" > /dev/null 2>&1 || { \
		LAYER_LATEST_ARN=$$(aws lambda list-layer-versions --layer-name "$(LAMBDA_LAYER_NAME)" | jq -r '.LayerVersions[0].LayerVersionArn'); \
	 	aws lambda create-function --function-name "$(LAMBDA_TEST_NAME)" \
			--architectures "$(LAMBDA_ARCH)" --runtime "provided.$(LAMBDA_RUNTIME)" \
			--layers "$$LAYER_LATEST_ARN" --handler "$(LAMBDA_TEST_HANDLER)" \
			--role "arn:aws:iam::$(AWS_ACCOUNT_ID):role/$(LAMBDA_EXECUTE_ROLE)" \
			--zip-file fileb://$<; \
	}
	@touch $@

# create function url for the test function
$(TS_FUNCTION_URL_CREATE): $(TS_FUNCTION_CREATE)
	aws lambda get-function-url-config --function-name "$(LAMBDA_TEST_NAME)" > /dev/null 2>&1 || \
		aws lambda create-function-url-config --function-name "$(LAMBDA_TEST_NAME)" \
			--auth-type "NONE" --cors '{ "AllowMethods": [ "GET", "POST" ], "AllowOrigins": ["*"] }'
	@touch $@

$(TS_FUNCTION_URL_PERMISSION): $(TS_FUNCTION_URL_CREATE)
	aws lambda get-policy --function-name "$(LAMBDA_TEST_NAME)" 2> /dev/null | grep 'Sid' > /dev/null || \
		aws lambda add-permission --function-name "$(LAMBDA_TEST_NAME)" \
			--statement-id FunctionURLAllowPublic --action lambda:InvokeFunctionUrl \
			--principal "*" --function-url-auth-type NONE
	@touch $@

# update function configuration to use the latest layer version
$(TS_FUNCTION_UPDATE_CONFIG): $(TS_FUNCTION_CREATE) $(TS_LAYER_PUBLISH)
	LAYER_LATEST_ARN=$$(aws lambda list-layer-versions --layer-name "$(LAMBDA_LAYER_NAME)" | jq -r '.LayerVersions[0].LayerVersionArn'); \
		aws lambda update-function-configuration --function-name "$(LAMBDA_TEST_NAME)" --layers "$$LAYER_LATEST_ARN" ; \
		sleep 5
	@touch $@

# update function code to use the latest test package
$(TS_FUNCTION_UPDATE_CODE): $(TESTS_PACKAGE) $(TS_FUNCTION_CREATE)
	aws lambda update-function-code --function-name "$(LAMBDA_TEST_NAME)" --zip-file fileb://$<
	@touch $@

test: $(TS_LAYER_PUBLISH) $(TS_FUNCTION_UPDATE_CONFIG) $(TS_FUNCTION_UPDATE_CODE) $(TS_FUNCTION_URL_PERMISSION)

# share latest version of layer for public use by all AWS accounts
public-share:
	LAYER_LATEST_VERSION=$$(aws lambda list-layer-versions --layer-name "$(LAMBDA_LAYER_NAME)" | jq -r '.LayerVersions[0].Version') ; \
		aws lambda add-layer-version-permission --layer-name "$(LAMBDA_LAYER_NAME)" --version-number "$$LAYER_LATEST_VERSION" --principal "*" --statement-id "php-runtime-public-share" --action lambda:GetLayerVersion

clean:
	rm -rf $(BUILD_DIR)
