<?php

declare(strict_types = 1);

require_once('/opt/php-runtime/Context.inc.php');

function testRequiredFunctions(): void
{
	// SimpleXML is required by the AWS SDK for PHP
	libxml_use_internal_errors(true);
	$sxe = new SimpleXMLElement('<test></test>');
}

function mainHandler(array $event, Context $ctx): array
{
	echo '*** PHP version: ' . phpversion() . "\n";

	testRequiredFunctions();

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
