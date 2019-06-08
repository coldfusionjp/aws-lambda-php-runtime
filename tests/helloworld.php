<?php

declare(strict_types = 1);

require_once('bootstrap-php/Context.inc.php');

function mainHandler(array $event, Context $ctx): array
{
	var_dump($ctx);
	$event['hello'] = 'world';
	echo "time remaining (msec): " . $ctx->getRemainingTimeInMsec() . "\n";

	$log = $ctx->getLogger();
	$log->setLevel(Logger::DEBUG);

	$log->debug("this is a debug log");
	$log->info("this is an info log");
	$log->warning("this is a warning log");
	$log->error("this is an error log");
	$log->critical("this is a critical log");

	return $event;
}
