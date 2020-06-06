<?php

// AWS Lambda PHP Runtime Layer (https://gitlab.com/coldfusionjp/aws-lambda-php-runtime)
// Copyright 2019 Cold Fusion, Inc.
//
// This file is subject to the terms and conditions as declared in the file 'LICENSE',
// which has been included as part of this source code package.

declare(strict_types = 1);

class AWSLambdaPHPRuntime
{
	public function __construct()
	{
		// enable all errors
		error_reporting(E_ALL | E_STRICT);

		// generate runtime endpoint
		$this->mEndpoint = "http://${_ENV['AWS_LAMBDA_RUNTIME_API']}/2018-06-01";

		// get lambda handler of desired user file.function to call
		$hpair = explode('.', $_ENV['_HANDLER']);
		if (count($hpair) < 2)
			$this->initializationError("Error: Lambda handler must be in 'file.function' format");

		// attempt to include the specified file
		$inc = "{$hpair[0]}.php";
		if (!include_once($inc))
			$this->initializationError("Error: Lambda handler file [{$inc}] not found");

		// and ensure the function exists
		if (!function_exists($hpair[1]))
			$this->initializationError("Error: Lambda handler function [{$hpair[1]}] not found in [{$inc}]");

		// store our handler function
		$this->mHandlerFunc = $hpair[1];

		// create our initial lambda context from the environment
		$this->mLambdaCtx = [
			'functionName'		=> $_ENV['AWS_LAMBDA_FUNCTION_NAME'] ?? null,
			'functionVersion'	=> $_ENV['AWS_LAMBDA_FUNCTION_VERSION'] ?? null,
			'memoryLimitInMB'	=> intval($_ENV['AWS_LAMBDA_FUNCTION_MEMORY_SIZE'] ?? 0),
			'logGroupName'		=> $_ENV['AWS_LAMBDA_LOG_GROUP_NAME'] ?? null,
			'logStreamName'		=> $_ENV['AWS_LAMBDA_LOG_STREAM_NAME'] ?? null
		];

		// if a cold start handler function exists, call it with our lambda context
		if (function_exists('coldStartHandler'))
		{
			// call the cold start handler function inside an exception handler (in case it throws)
			try
			{
				coldStartHandler($this->mLambdaCtx);
			}
			catch (Exception $e)
			{
				// dump exception to stdout (which gets sent to CloudWatch)
				error_log("{$e}");

				// then call the lambda initialization error handler to abort the lambda
				$str = 'Error: Lambda cold start handler function failed with message=[' . $e->getMessage() . '], stacktrace=[' . $e->getTrace() . ']';
				$this->initializationError($str);
			}
		}
	}

	private function getCurlOptions(): array
	{
		// we set curl to wait forever (CURLOPT_TIMEOUT of 0) for a response from Lambda.  from https://github.com/awslabs/aws-lambda-cpp/blob/master/src/runtime.cpp:
		//   "lambda freezes the container when no further tasks are available. The freezing period could be longer than the
		//    request timeout, which causes the following get_next request to fail with a timeout error."
		return [
			CURLOPT_TIMEOUT			=> 0,
			CURLOPT_CONNECTTIMEOUT	=> 1,
			CURLOPT_NOSIGNAL		=> true,
			CURLOPT_TCP_NODELAY		=> true,
			CURLOPT_RETURNTRANSFER	=> true
		];
	}

	private function lambdaGet(string $uri, array &$headers): string
	{
		$ctx = curl_init($uri);
		curl_setopt_array($ctx, $this->getCurlOptions() + [
			CURLOPT_HEADERFUNCTION	=> function($ctx, $header) use (&$headers) {
				// split header
				$len = strlen($header);
				$hdr = explode(':', $header, 2);

				// ignore any invalid headers (without a colon)
				if (count($hdr) < 2)
					return $len;

				// convert key to lowercase and add header to array
				$name = strtolower(trim($hdr[0]));
				if (!array_key_exists($name, $headers))
					$headers[$name] = [ trim($hdr[1]) ];
				else
					$headers[$name][] = trim($hdr[1]);

				return $len;
			}
		] );

		$body = curl_exec($ctx);
		curl_close($ctx);
		return $body;
	}

	private function lambdaPost(string $uri, string $body): void
	{
		$ctx = curl_init($uri);
		curl_setopt_array($ctx, $this->getCurlOptions() + [
			CURLOPT_POST			=> true,
			CURLOPT_POSTFIELDS		=> $body
		] );

		curl_exec($ctx);
		curl_close($ctx);
	}

	private function nextInvocation(): array
	{
		$headers = [];
		$body = $this->lambdaGet("{$this->mEndpoint}/runtime/invocation/next", $headers);

		// create request context from received headers
		$this->mRequestCtx = [
			'awsRequestID'			=> $headers['lambda-runtime-aws-request-id'][0] ?? null,
			'deadlineMsec'			=> intval($headers['lambda-runtime-deadline-ms'][0] ?? 0),
			'invokedFunctionARN'	=> $headers['lambda-runtime-invoked-function-arn'][0] ?? null,
			'traceID'				=> $headers['lambda-runtime-trace-id'][0] ?? null,
			'clientContext'			=> $headers['lambda-runtime-client-context'][0] ?? null,
			'identity'				=> $headers['lambda-runtime-cognito-identity'][0] ?? null
		];

		// propagate the X-Ray tracing header to both the PHP environment and any child environment
		// see "Processing Tasks" at bottom of page here: https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html
		$xray = $this->mRequestCtx['traceID'];
		$_ENV['_X_AMZN_TRACE_ID'] = $xray;
		putenv("_X_AMZN_TRACE_ID={$xray}");

		// attempt to decode the incoming request JSON
		$arr = json_decode($body, true);

		// if the decode failed for any reason, recreate it as an empty array (so the user code can either handle or error on any lack of data by itself)
		if (!is_array($arr))
			$arr = [];

		return $arr;
	}

	private function invocationResponse(array $response): void
	{
		// encode response and post to response endpoint
		$body = json_encode($response, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
		$this->lambdaPost("{$this->mEndpoint}/runtime/invocation/{$this->mRequestCtx['awsRequestID']}/response", $body);
	}

	private function invocationError(array $response): void
	{
		// encode response and post to error endpoint
		$body = json_encode($response, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
		$this->lambdaPost("{$this->mEndpoint}/runtime/invocation/{$this->mRequestCtx['awsRequestID']}/error", $body);
	}

	private function initializationError(string $msg): void
	{
		// send message to initialization endpoint and exit
		$this->lambdaPost("{$this->mEndpoint}/runtime/init/error", $msg);
		exit(1);
	}

	public function run(): void
	{
		// loop forever, processing requests
		for (;;)
		{
			// get next lambda invocation request
			$req = $this->nextInvocation();

			// create context array, combining both lambda environment and request contexts
			$ctx = $this->mLambdaCtx + $this->mRequestCtx;

			try
			{
				// call user handler
				$resp = call_user_func($this->mHandlerFunc, $req, $ctx);

				// and return lambda response
				$this->invocationResponse($resp);
			}
			catch (Exception $e)
			{
				// dump exception to stdout (which gets sent to CloudWatch)
				error_log("{$e}");

				// then get message and stacktrace from exception, and call lambda invocation error
				$this->invocationError( [
					'errorMessage'	=> $e->getMessage(),
					'stackTrace'	=> $e->getTrace(),
					'errorType'		=> 'Exception'
				] );
			}
		}
	}

	private ?string			$mEndpoint	  = null;
	private /*?callable*/	$mHandlerFunc = null;
	private ?array			$mLambdaCtx   = null;
	private ?array			$mRequestCtx  = null;
}

$runtime = new AWSLambdaPHPRuntime();
$runtime->run();
