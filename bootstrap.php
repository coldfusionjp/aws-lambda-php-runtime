<?php

declare(strict_types = 1);

class AWSLambdaPHPRuntime
{
	private $mEndpoint  = null;
	private $mRequestID = null;

	public function __construct()
	{
		// enable all errors
		error_reporting(E_ALL | E_STRICT);

		// generate runtime endpoint
		$this->mEndpoint = "http://${_ENV['AWS_LAMBDA_RUNTIME_API']}/2018-06-01";
	}

	private function lambdaGet(string $uri, array &$headers): string
	{
		$ctx = curl_init($uri);
		curl_setopt_array($ctx, [
			CURLOPT_RETURNTRANSFER	=> true,
			CURLOPT_TCP_NODELAY		=> true,
			CURLOPT_HEADERFUNCTION	=> function($ctx, $header) use (&$headers) {
				$len = strlen($header);
				$hdr = explode(':', $header, 2);

				// ignore invalid headers
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

	private function lambdaPost(string $uri, string $body)
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
		return json_decode($body, true);
	}

	private function invocationResponse(array $response)
	{
		$body = json_encode($response);
		$this->lambdaPost("{$this->mEndpoint}/runtime/invocation/{$this->mRequestID}/response", $body);
	}

	public function run()
	{
		for (;;)
		{
			$resp = $this->nextInvocation();
			$resp['hello'] = 'world';
			$this->invocationResponse($resp);
		}
	}
}

$runtime = new AWSLambdaPHPRuntime();
$runtime->run();
