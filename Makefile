PHP_VERSIONS		:= php-7.3.6 php-7.3.7 php-7.3.8 php-7.3.9

# generate a list of output targets for each PHP version
OUTPUT_TARGETS		:= $(foreach ver, $(PHP_VERSIONS), build/$(ver)-runtime.zip)

#------------------------------------------------------------------------

SOURCES				:= src/bootstrap $(shell find src -name "*.php")
TEST_SOURCES		:= $(shell find tests -name "*.php")
SHELL				:= /bin/bash

UNAME_OS			:= $(shell uname -s)
ifeq ($(UNAME_OS),Darwin)
BASE64_DECODE		:= base64 --decode
else
BASE64_DECODE		:= base64 -d
endif

AWS_ACCOUNT_ID		?= $(shell aws sts get-caller-identity | jq -r .Account)
AWS_DEFAULT_REGION	?= $(shell aws configure get region)
LAMBDA_TEST_NAME	:= php-runtime-tests
LAMBDA_EXECUTE_ROLE	:= lambda-basic-execute
LAMBDA_TEST_HANDLER	:= helloworld.mainHandler

#------------------------------------------------------------------------

# return the version of an output target (7.3.6)
define phpVersion
$(word 2,$(subst -, ,$(1)))
endef

# return the full tag of an output target (php-7.3.6)
define phpTag
$(subst build/,,$(word 1,$(subst -, ,$(1))))-$(call phpVersion,$(1))
endef

# return the AWS Lambda layer name of an output target (php-7_3_6)
define lambdaLayerName
$(subst .,_,$(call phpTag,$(1)))
endef

# generate a rule to build a given output target
define generateBuildRule
$(target): Dockerfile
	@mkdir -p $$(dir $$@)
	time docker build --build-arg PHP_VERSION="$$(call phpTag,$$@)" -t "coldfusionjp/aws-lambda-php-runtime:$$(call phpVersion,$$@)" -f $$< . | tee build/$$(call phpTag,$$@).log ; exit "$$$${PIPESTATUS[0]}"
	docker run -v $$(PWD)/src/php-runtime/bin:/mnt --rm --entrypoint cp "coldfusionjp/aws-lambda-php-runtime:$$(call phpVersion,$$@)" /opt/php/bin/php /mnt
	cd src && zip -v -9 -r ../$$@ *
	aws lambda publish-layer-version --layer-name "$$(call lambdaLayerName,$$@)-runtime" --description "PHP $$(call phpVersion,$$@) Runtime, by Cold Fusion, Inc. For more details and version updates, see: https://gitlab.com/coldfusionjp/aws-lambda-php-runtime" --license-info "For license info, see: https://gitlab.com/coldfusionjp/aws-lambda-php-runtime#license" --zip-file fileb://$$@
endef

#------------------------------------------------------------------------

.DELETE_ON_ERROR:

default: $(OUTPUT_TARGETS)

$(foreach target, $(OUTPUT_TARGETS), $(eval $(generateBuildRule)))

# package test functions
build/tests.zip: $(TEST_SOURCES)
	@rm -f $@
	@mkdir -p $(dir $@)
	cd tests && zip -v -9 -r ../$@ *	

# create lambda function required for testing
test-create-function: build/tests.zip
	aws lambda create-function --function-name "$(LAMBDA_TEST_NAME)" --role "arn:aws:iam::$(AWS_ACCOUNT_ID):role/$(LAMBDA_EXECUTE_ROLE)" --runtime provided --handler "$(LAMBDA_TEST_HANDLER)" --zip-file fileb://$<

# update runtime test code and invoke lambda using the latest runtime layer for each supported PHP version
test: build/tests.zip
	aws lambda update-function-code --function-name "$(LAMBDA_TEST_NAME)" --zip-file fileb://$<
	@for version in $(PHP_VERSIONS); do \
		LAYER_NAME=`echo $${version}-runtime | sed "s/\./_/g"` ; \
		LAYER_LATEST_ARN=`aws lambda list-layer-versions --layer-name "$${LAYER_NAME}" | jq -r '.LayerVersions[0].LayerVersionArn'` ; \
		aws lambda update-function-configuration --function-name "$(LAMBDA_TEST_NAME)" --layers "$${LAYER_LATEST_ARN}" ; \
		aws lambda invoke --invocation-type RequestResponse --function-name "$(LAMBDA_TEST_NAME)" --log-type Tail --payload '{"key1":"value1","key2":"value2","key3":"value3"}' response.txt > log.txt ; \
		echo 'Response:' ; \
		cat response.txt ; \
		echo '' ; \
		echo '' ; \
		echo 'Logs:' ; \
		cat log.txt | jq -r '.LogResult' | $(BASE64_DECODE) ; \
		rm -f response.txt log.txt ; \
	done

clean:
	rm -rf build
