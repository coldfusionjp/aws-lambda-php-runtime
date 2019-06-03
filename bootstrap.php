<?php

error_reporting(E_ALL | E_STRICT);

echo "Hello world from PHP!\n";

class AWSLambdaPHPRuntime
{
	private function httpMethod($method, $uri, $params = null, $timeout = 5, $userAgent = null) : string
	{
		$opts = [
			'http'  => [
			'method'    => $method,
			'timeout'   => $timeout,
			'header'    => []
			]
		];

		// attach params, if specified
		if (!empty($params))
		{
			array_push($opts['http']['header'], 'Content-type: application/x-www-form-urlencoded');
			$opts['http']['content'] = http_build_query($params);
		}

		// set user agent, if specified
		if ($userAgent != null)
			$opts['http']['user_agent'] = $userAgent;

		$ctx = stream_context_create($opts);
		return file_get_contents($uri, 0, $ctx);
	}

	private function httpGet($uri, $timeout = 5) : string
	{
		return $this->httpMethod('GET', $uri, null, $timeout);
	}

	private function httpPost($uri, $params = null, $timeout = 5, $userAgent = null) : string
	{
		return $this->httpMethod('POST', $uri, $params, $timeout, $userAgent);
	}

	public function error()
	{
		$this->httpPost("http://${_ENV['AWS_LAMBDA_RUNTIME_API']}/2018-06-01/runtime/init/error");
	}
}

echo "creating PHP runtime...\n";
$runtime = new AWSLambdaPHPRuntime();
echo "about to error...\n";
$runtime->error();
echo "error done\n";
