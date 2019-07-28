PHP_VERSION			:= php-7.3.6

AWS_ACCOUNT_ID		?= $(shell aws sts get-caller-identity | jq -r .Account)
AWS_DEFAULT_REGION	?= $(shell aws configure get region)

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

#------------------------------------------------------------------------

.DELETE_ON_ERROR:

default: build/php-runtime.zip

# build a Docker image given a Dockerfile
build/%.log: %/Dockerfile
	@mkdir -p $(dir $@)
	time docker build --build-arg PHP_VERSION="$(PHP_VERSION)" -t coldfusionjp/aws-lambda-php-runtime:latest $(<D) | tee $@ ; exit "$${PIPESTATUS[0]}"

# extract php binary from built Docker image
runtime/CFPHPRuntime/bin/php: build/php-builder.log
	@mkdir -p $(dir $@)
	docker run -v $(PWD)/$(dir $@):/mnt --rm --entrypoint cp coldfusionjp/aws-lambda-php-runtime:latest /opt/php/bin/php /mnt

# compress runtime package and upload to AWS Lambda
build/php-runtime.zip: $(SOURCES) runtime/CFPHPRuntime/bin/php
	@rm -f $@
	cd runtime && zip -v -9 -r ../$@ *
	aws lambda publish-layer-version --layer-name php-runtime --description "PHP Runtime" --zip-file fileb://$@

# package test functions
build/tests.zip: $(TEST_SOURCES)
	@rm -f $@
	@mkdir -p $(dir $@)
	cd tests && zip -v -9 -r ../$@ *

# create lambda function for testing (only needs to be manually performed once, not used by CI)
test-create: build/tests.zip
	aws lambda create-function --function-name php-runtime-tests --role "arn:aws:iam::$(AWS_ACCOUNT_ID):role/lambda-basic-execute" --layers "arn:aws:lambda:$(AWS_DEFAULT_REGION):$(AWS_ACCOUNT_ID):layer:php-runtime:1" --runtime provided --handler "helloworld.mainHandler" --zip-file fileb://$<

# push runtime tests and invoke lambda
test: build/tests.zip
	aws lambda update-function-code --function-name php-runtime-tests --zip-file fileb://$<
	aws lambda invoke --invocation-type RequestResponse --function-name php-runtime-tests --log-type Tail --payload '{"key1":"value1","key2":"value2","key3":"value3"}' response.txt > log.txt
	@echo 'Response:'
	@cat response.txt
	@echo ''
	@echo ''
	@echo 'Logs:'
	@cat log.txt | jq -r '.LogResult' | $(BASE64_DECODE)
	@rm -f response.txt log.txt

clean:
	rm -rf build
