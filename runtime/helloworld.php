<?php

declare(strict_types = 1);

function mainHandler(array $event): array
{
	$event['hello'] = 'world';
	return $event;
}
