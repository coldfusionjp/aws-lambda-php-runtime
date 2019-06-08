.SUFFIXES:
.DELETE_ON_ERROR:

DOCKER_REPOSITORY	:= registry.gitlab.com/coldfusionjp/private/awslambdaphpruntime

#------------------------------------------------------------------------

SHELL				:= /bin/bash
SOURCES				:= runtime/bootstrap runtime/bootstrap-php/bootstrap.php runtime/bootstrap-php/Context.inc.php runtime/bootstrap-php/Logger.inc.php

#------------------------------------------------------------------------

default: build/php-runtime.zip

# allow GitLab CI instance to authenticate to GitLab Container Registry using GitLab predefined environment variables (avoids need for an access token)
# note that this is not necessary when running builds on a local machine, as the user should already be authenticated using his/her own access key.
login:
	docker login -u $(CI_REGISTRY_USER) -p $(CI_JOB_TOKEN) $(CI_REGISTRY)

# build a Docker image given a Dockerfile
# since we intend to run this script on GitLab provided CI instances, we first prime the Docker cache by pulling the image from the GitLab Docker repository.
# the image build step then uses --cache-from to ensure the layers of the pulled Docker image is used in the build process to avoid a complete rebuild every time.
# note: there currently is a Docker/GitLab CI bug where the previous pulled layers are not reused as a cache, so we also pull the base FROM image as well.
# see: https://github.com/moby/moby/issues/31613#issuecomment-342857930
build/%.log: %/Dockerfile
	@mkdir -p $(dir $@)
	docker pull `grep -i FROM $< | head -n 1 | awk '{print $$2}'` 
	docker pull $(DOCKER_REPOSITORY)/$(<D):latest || true
	docker build --cache-from $(DOCKER_REPOSITORY)/$(<D):latest --tag $(DOCKER_REPOSITORY)/$(<D):latest $(<D) | tee $@ ; exit "$${PIPESTATUS[0]}"
	docker push $(DOCKER_REPOSITORY)/$(<D):latest

# extract php binary from built Docker image
runtime/bootstrap-php/bin/php: build/php-builder.log
	@mkdir -p $(dir $@)
	docker run -v $(PWD)/$(dir $@):/mnt --rm --entrypoint cp $(DOCKER_REPOSITORY)/php-builder:latest /opt/php/bin/php /mnt

# compress runtime package and upload to AWS Lambda
build/php-runtime.zip: $(SOURCES) runtime/bootstrap-php/bin/php
	cd runtime && zip -v -9 -r ../$@ *
	aws lambda publish-layer-version --layer-name php7-runtime --description "PHP 7 Custom Runtime" --zip-file fileb://$@

clean:
	rm -rf build

#------------------------------------------------------------------------
# disable implicit prerequisite rules for RCS and SCCS
#------------------------------------------------------------------------
%: %,v
%: RCS/%,v
%: RCS/%
%: s.%
%: SCCS/s.%
