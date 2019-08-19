PHP_VERSIONS		:= php-7.3.6 php-7.3.7 php-7.3.8

# generate a list of output targets for each PHP version
OUTPUT_TARGETS		:= $(foreach ver, $(PHP_VERSIONS), build/$(ver)-runtime.zip)

#------------------------------------------------------------------------

SOURCES				:= runtime/bootstrap runtime/CFPHPRuntime/bootstrap.php runtime/CFPHPRuntime/Context.inc.php runtime/CFPHPRuntime/Logger.inc.php
TEST_SOURCES		:= tests/helloworld.php
SHELL				:= /bin/bash

UNAME_OS			:= $(shell uname -s)
ifeq ($(UNAME_OS),Darwin)
BASE64_DECODE		:= base64 --decode
else
BASE64_DECODE		:= base64 -d
endif

AWS_ACCOUNT_ID		?= $(shell aws sts get-caller-identity | jq -r .Account)
AWS_DEFAULT_REGION	?= $(shell aws configure get region)
LAMBDA_EXECUTE_ROLE	:= lambda-basic-execute

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

# return the AWS Lambda function name for a testing target (php-7_3_6-runtime-tests)
define lambdaFunctionTestName
$(call lambdaLayerName,$(1))-runtime-tests
endef

# generate a rule to build a given output target
define generateBuildRule
$(target): Dockerfile
	@mkdir -p $$(dir $$@)
	time docker build --build-arg PHP_VERSION="$$(call phpTag,$$@)" -t "coldfusionjp/aws-lambda-runtime:$$(call phpTag,$$@)" -f $$< . | tee build/$$(call phpTag,$$@).log ; exit "$$$${PIPESTATUS[0]}"
	docker run -v $$(PWD)/runtime/CFPHPRuntime/bin:/mnt --rm --entrypoint cp "coldfusionjp/aws-lambda-runtime:$$(call phpTag,$$@)" /opt/php/bin/php /mnt
	cd runtime && zip -v -9 -r ../$$@ *
	aws lambda publish-layer-version --layer-name "$$(call lambdaLayerName,$$@)-runtime" --description "PHP $$(call phpVersion,$$@) Runtime" --zip-file fileb://$$@
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

# create lambda functions required for testing
test-create-functions: build/tests.zip
	@for version in $(PHP_VERSIONS); do \
		LAYER_NAME=`echo $${version}-runtime | sed "s/\./_/g"` ; \
		FUNCTION_NAME=`echo $${version}-runtime-tests | sed "s/\./_/g"` ; \
		LAYER_LATEST_ARN=`aws lambda list-layer-versions --layer-name "$${LAYER_NAME}" | jq -r '.LayerVersions[0].LayerVersionArn'` ; \
		FUNCTION_CHECK=`aws lambda get-function-configuration --function-name "$${FUNCTION_NAME}" 2>&1 | jq -r '.FunctionName'` ; \
		if [ "$${FUNCTION_CHECK}" != "$${FUNCTION_NAME}" ] ; then \
			echo "Function \"$${FUNCTION_NAME}\" does not exist on AWS Lambda, creating..." ; \
			aws lambda create-function --function-name "$${FUNCTION_NAME}" --role "arn:aws:iam::$(AWS_ACCOUNT_ID):role/$(LAMBDA_EXECUTE_ROLE)" --layers "$${LAYER_LATEST_ARN}" --runtime provided --handler "helloworld.mainHandler" --zip-file fileb://$< ; \
		fi ; \
	done

# push runtime tests and invoke lambda
test: build/tests.zip
	@for version in $(PHP_VERSIONS); do \
		LAYER_NAME=`echo $${version}-runtime | sed "s/\./_/g"` ; \
		FUNCTION_NAME=`echo $${version}-runtime-tests | sed "s/\./_/g"` ; \
		LAYER_LATEST_ARN=`aws lambda list-layer-versions --layer-name "$${LAYER_NAME}" | jq -r '.LayerVersions[0].LayerVersionArn'` ; \
		FUNCTION_CHECK=`aws lambda get-function-configuration --function-name "$${FUNCTION_NAME}" 2>&1 | jq -r '.FunctionName'` ; \
		if [ "$${FUNCTION_CHECK}" != "$${FUNCTION_NAME}" ] ; then \
			echo "Function \"$${FUNCTION_NAME}\" does not exist on AWS Lambda, please run \"make test-create-functions\" first!" ; \
			exit 1 ; \
		fi ; \
		aws lambda update-function-configuration --function-name "$${FUNCTION_NAME}" --layers "$${LAYER_LATEST_ARN}" ; \
		aws lambda update-function-code --function-name "$${FUNCTION_NAME}" --zip-file fileb://$< ; \
		aws lambda invoke --invocation-type RequestResponse --function-name "$${FUNCTION_NAME}" --log-type Tail --payload '{"key1":"value1","key2":"value2","key3":"value3"}' response.txt > log.txt ; \
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
