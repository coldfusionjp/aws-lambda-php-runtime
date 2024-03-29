<?php

declare(strict_types = 1);

require_once('/opt/php-runtime/Context.inc.php');

function testRequiredFunctions(): void
{
	// SimpleXML is required by the AWS SDK for PHP
	libxml_use_internal_errors(true);
	$sxe = new SimpleXMLElement('<test></test>');
}

function coldStartHandler(array $ctx): void
{
	echo "*** coldStartHandler ***\n";
	echo 'context=[' . print_r($ctx, true) . "]\n";
}

function mainHandler(array $event, array $ctx): array
{
	echo "*** mainHandler ***\n";
	echo 'PHP version: ' . phpversion() . "\n";

	testRequiredFunctions();

	// create context object from context
	$cobj = new Context($ctx);
	var_dump($cobj);
	$event['hello'] = 'world';
	echo "time remaining (msec): " . $cobj->getRemainingTimeInMsec() . "\n";

	$log = $cobj->getLogger();
	$log->setLevel(Logger::DEBUG);

	$log->debug("this is a debug log");
	$log->info("this is an info log");
	$log->warning("this is a warning log");
	$log->error("this is an error log");
	$log->critical("this is a critical log");

	return $event;
}
