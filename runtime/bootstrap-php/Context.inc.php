<?php

declare(strict_types = 1);

class Context
{
	private $mProperties = null;

	public function __construct(array $properties)
	{
		$this->mProperties = $properties;
	}

	public function __get(string $key): ?mixed
	{
		if (!array_key_exists($key, $this->mProperties))
			return null;

		return $this->mProperties[$key];
	}

	public function getRemainingTimeInMsec(): int
	{
		// get current time and calculate milliseconds
		$time = gettimeofday();
		$msec = intval($time['sec'] * 1000) + intval($time['usec'] / 1000);

		// subtract from context deadline time to determine remaining time
		return $this->mProperties['deadlineMsec'] - $msec;
	}
}
