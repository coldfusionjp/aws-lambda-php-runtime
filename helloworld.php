<?php

function hello($in)
{
	$in['hello'] = 'world';
	throw new Exception("ohno");
	return $in;
}
