<?php

$in = stream_get_contents(STDIN);
$json = json_decode($in, true);

$json['hello'] = 'world';

echo json_encode($json);
