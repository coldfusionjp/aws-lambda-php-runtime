<?php

declare(strict_types = 1);

class AWSLambdaPHPRuntime
{
	private $mEndpoint	= null;
	private $mRequestID	= null;
	private $mHandler	= null;

	public function __construct()
	{
		// enable all errors
		error_reporting(E_ALL | E_STRICT);

		// generate runtime endpoint
		$this->mEndpoint = "http://${_ENV['AWS_LAMBDA_RUNTIME_API']}/2018-06-01";

		// get lambda handler of desired user file.function to call
		$handler = getenv('_HANDLER');
		$hpair = explode('.', $handler);
		if (count($hpair) < 2)
			$this->initializationError("Error: Lambda handler must be in 'file.function' format");

		// attempt to include the specified file
		$inc = "{$hpair[0]}.php";
		if (!include_once($inc))
			$this->initializationError("Error: Lambda handler file [{$inc}] not found");

		// and ensure the function exists
		if (!function_exists($hpair[1]))
			$this->initializationError("Error: Lambda handler function [{$hpair[1]}] not found in [{$inc}]");

		// store our function handler
		$this->mHandler = $hpair[1];
	}

	private function lambdaGet(string $uri, array &$headers): string
	{
		$ctx = curl_init($uri);
		curl_setopt_array($ctx, [
			CURLOPT_RETURNTRANSFER	=> true,
			CURLOPT_TCP_NODELAY		=> true,
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
		curl_setopt_array($ctx, [
			CURLOPT_RETURNTRANSFER	=> true,
			CURLOPT_TCP_NODELAY		=> true,
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

		// store lambda request ID
		$this->mRequestID = $headers['lambda-runtime-aws-request-id'][0];

		// propagate the X-Ray tracing header to both the PHP environment and any child environment
		$xray = $headers['lambda-runtime-trace-id'][0];
		$_ENV['_X_AMZN_TRACE_ID'] = $xray;
		putenv("_X_AMZN_TRACE_ID={$xray}");

		// attempt to decode the incoming request JSON
		$arr = json_decode($body, true);

		// if the decode failed for any reason, recreate it as an empty array (so the user code can either handle or error on any lack of data itself)
		if (!is_array($arr))
			$arr = [];

		return $arr;
	}

	private function invocationResponse(array $response): void
	{
		$body = json_encode($response, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
		$this->lambdaPost("{$this->mEndpoint}/runtime/invocation/{$this->mRequestID}/response", $body);
	}

	private function invocationError(array $response): void
	{
		$body = json_encode($response, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
		$this->lambdaPost("{$this->mEndpoint}/runtime/invocation/{$this->mRequestID}/error", $body);
	}

	private function initializationError(string $msg): void
	{
		$this->lambdaPost("{$this->mEndpoint}/runtime/init/error", $msg);
		exit(1);
	}

	public function run(): void
	{
		for (;;)
		{
			// get next lambda invocation request
			$req = $this->nextInvocation();

			try
			{
				// attempt to call user handler
				$resp = call_user_func($this->mHandler, $req);

				// return lambda response
				$this->invocationResponse($resp);
			}
			catch (Exception $e)
			{
				// dump exception to stdout (which gets sent to CloudWatch)
				error_log("{$e}");

				// then get message and stacktrace from exception and call lambda invocation error
				$this->invocationError( [
					'errorMessage'	=> $e->getMessage(),
					'stackTrace'	=> $e->getTrace(),
					'errorType'		=> 'Exception'
				] );
			}
		}
	}
}

$runtime = new AWSLambdaPHPRuntime();
$runtime->run();
