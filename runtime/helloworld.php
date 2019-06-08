<?php

declare(strict_types = 1);

require_once('bootstrap-php/Context.inc.php');

function mainHandler(array $event, Context $ctx): array
{
	var_dump($ctx);
	$event['hello'] = 'world';
	echo "time remaining, before sleep (msec): " . $ctx->getRemainingTimeInMsec();
	sleep(1);
	echo "time remaining, after sleep (msec): " . $ctx->getRemainingTimeInMsec();
	return $event;
}
