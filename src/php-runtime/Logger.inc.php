<?php

declare(strict_types = 1);

class Logger
{
	public const DEBUG		= 0;
	public const INFO		= 1;
	public const WARNING	= 2;
	public const ERROR		= 3;
	public const CRITICAL	= 4;

	private const kLogLevelStrings = [
		self::DEBUG			=> '[DEBUG]   ',
		self::INFO			=> '[INFO]    ',
		self::WARNING		=> '[WARNING] ',
		self::ERROR			=> '[ERROR]   ',
		self::CRITICAL		=> '[CRITICAL]'
	];

	private $mLogLevel  = self::INFO;
	private $mRequestID = null;

	public function __construct(string $requestID)
	{
		$this->mRequestID = $requestID;
	}

	public function setLevel(int $level): void
	{
		$this->mLogLevel = $level;
	}

	public function log(int $level, string $msg): void
	{
		// skip writing message if level of this message is lower than the current log level
		if ($level < $this->mLogLevel)
			return;

		// lookup level string for this message
		$lvl  = self::kLogLevelStrings[$level] ?? '';

		// format current time as a RFC3339 extended date/time/msec into a string
		$date = new DateTime();
		$time = $date->format(DATE_RFC3339_EXTENDED);

		// format and write message to stdout
		echo "{$lvl}  {$time}  {$this->mRequestID}  {$msg}\n";
	}

	public function debug(string $msg): void
	{
		$this->log(self::DEBUG, $msg);
	}

	public function info(string $msg): void
	{
		$this->log(self::INFO, $msg);
	}

	public function warning(string $msg): void
	{
		$this->log(self::WARNING, $msg);
	}

	public function error(string $msg): void
	{
		$this->log(self::ERROR, $msg);
	}

	public function critical(string $msg): void
	{
		$this->log(self::CRITICAL, $msg);
	}
}
