# AWS Lambda PHP Runtime Layer

[![pipeline status](https://gitlab.com/coldfusionjp/aws-lambda-php-runtime/badges/master/pipeline.svg)](https://gitlab.com/coldfusionjp/aws-lambda-php-runtime/commits/master)

The **AWS Lambda PHP Runtime Layer** is an implementation of a custom lambda runtime to provide direct PHP language support with AWS Lambda, packaged into an easy-to-use lambda layer.  The latest versions of PHP 7.3+ are provided, with the PHP binary built directly from the [source distributions available at php.net](https://www.php.net/distributions/).

## Quickstart

If you want to get started right away, you can simply use our layers directly with your lambda functions.  Choose an ARN below based on the version of PHP required by your application, and attach it as a layer to your lambda function:

### PHP 7.4 (compiled with clang/llvm-9.0.1)

* php-7.4.1: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_4_1-runtime:8` (2,531,662 bytes)
* php-7.4.0: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_4_0-runtime:9` (2,531,586 bytes)

### PHP 7.3 (compiled with clang/llvm-8.0.1)

* php-7.3.13: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_3_13-runtime:1` (2,505,365 bytes)
* php-7.3.12: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_3_12-runtime:1` (2,505,172 bytes)
* php-7.3.11: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_3_11-runtime:1` (2,505,948 bytes)
* php-7.3.10: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_3_10-runtime:1` (2,505,488 bytes)
* php-7.3.9: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_3_9-runtime:7` (2,476,686 bytes)
* php-7.3.8: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_3_8-runtime:10` (2,478,896 bytes)
* php-7.3.7: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_3_7-runtime:15` (2,478,802 bytes)
* php-7.3.6: `arn:aws:lambda:ap-northeast-1:568458425968:layer:php-7_3_6-runtime:21` (2,477,764 bytes)

Currently we only provide the PHP Runtime Layers in the Tokyo (`ap-northeast-1`) region, but we'll expand this soon so they're available in all AWS regions.

## Example Code

Combined with the [AWS SDK for PHP Lambda Layer](https://gitlab.com/coldfusionjp/aws-sdk-php-lambda-layer), performing AWS operations with Lambda in PHP only requires a few lines of code:

```
<?php

require_once('/opt/php-runtime/Context.inc.php');
require_once('/opt/aws-sdk-php/aws-autoloader.php');

use Aws\Sdk;

function mainHandler(array $event, Context $ctx): array
{
	// initialize AWS SDK
	$aws = new Aws\Sdk;

	// write object to S3
	$s3 = $aws->createS3( [
		'version'			=> '2006-03-01',
		'region'			=> 'us-east-1'
	] );

	$res = $s3->putObject( [
		'Bucket'			=> 'mybucket',
		'Key'				=> 'path/event.txt',
		'Body'				=> $event['text']
	] );
}
```

## Overview

A Dockerfile based on Amazon Linux (using the same runtime as Lambda) downloads the PHP source code directly from php.net, and builds a single PHP CLI binary using `clang`, with optimizations tweaked specifically for size.  For example, the `CodeSize` for the entire php-7.3.9 runtime layer is **2.36MB**, allowing the lambda function to quickly perform a cold startup.  Our unit tests execute in roughly 200ms for a cold start, while a warm start fully executes in _only 17ms_.

The Amazon Linux Docker image with a prepackaged `clang` compiler is built using [our Docker scripts](https://gitlab.com/coldfusionjp/build-clang-llvm), and the images are available on [Docker Hub](https://hub.docker.com/r/coldfusionjp/amazonlinux-clang).

## License

The source implementation of the AWS Lambda PHP Runtime Layer found in this repository is distributed by Cold Fusion, Inc. under the [MIT License](https://choosealicense.com/licenses/mit/), however PHP 7 itself is distributed under the [PHP License v3.01](https://www.php.net/license/3_01.txt).

See [LICENSE](./LICENSE) for more information.
