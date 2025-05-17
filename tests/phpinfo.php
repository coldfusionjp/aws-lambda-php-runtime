<?php

declare(strict_types = 1);

require_once('/opt/php-runtime/LambdaContext.inc.php');

function maskCredentials(string $content, array $keys): string
{
	foreach ($keys as $key) {
		// match both "KEY => value" and array key format "['KEY'] => value"
		$pattern = '/(\[\'' . preg_quote($key, '/') . '\'\]|' . preg_quote($key, '/') . ') => ([^\s\n\r]*)/';
		$content = preg_replace_callback($pattern, function($matches) use ($key) {
			$prefix = $matches[1];
			$value = $matches[2];
			$length = strlen($value);
			if (str_starts_with($prefix, "['")) {
				return $prefix . ' => ' . str_repeat('X', $length);
			} else {
				return $key . ' => ' . str_repeat('X', $length);
			}
		}, $content);
	}
	
	return $content;
}

function lambdaHandler(array $event, LambdaContext $ctx): array
{
	// capture phpinfo output into a string (we can only get pure text output as PHP is invoked in CLI mode)
	ob_start();
	phpinfo(INFO_ALL);
	$body = ob_get_clean();

	// mask out any AWS credentials from the output
	$body = maskCredentials($body, [
		'AWS_SECRET_ACCESS_KEY',
		'AWS_ACCESS_KEY_ID',
		'AWS_SESSION_TOKEN'
	] );

	// return an event to instruct lambda to show the body as plain text
	return [
		'statusCode' => 200,
		'headers' => [
			'Content-Type' => 'text/plain; charset=utf-8',
		],
		'body' => $body
	];
}
