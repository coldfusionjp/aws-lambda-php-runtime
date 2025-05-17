<?php
/*
 * AWS Lambda PHP Runtime Layer (https://github.com/coldfusionjp/aws-lambda-php-runtime)
 * Copyright 2019-2025 Cold Fusion, Inc.
 *
 * This file is subject to the terms and conditions as declared in the file 'LICENSE',
 * which has been included as part of this source code package.
 */

declare(strict_types = 1);

require_once('LambdaLogger.inc.php');

class LambdaContext
{
	public function __construct(array $properties)
	{
		// store properties and create a logger object, passing the lambda request ID if available
		$this->mProperties = $properties;
		$this->mLogger	   = new LambdaLogger($this->mProperties['awsRequestID'] ?? '');
	}

	public function __get(string $key): mixed
	{
		return $this->mProperties[$key] ?? null;
	}

	public function getRemainingTimeInMsec(): int
	{
		// get current time and calculate milliseconds
		$time = gettimeofday();
		$msec = intval($time['sec'] * 1000) + intval($time['usec'] / 1000);

		// subtract from context deadline time to determine remaining time
		return $this->mProperties['deadlineMsec'] - $msec;
	}

	public function getLogger(): LambdaLogger
	{
		return $this->mLogger;
	}

	private array		 $mProperties;
	private LambdaLogger $mLogger;
}
