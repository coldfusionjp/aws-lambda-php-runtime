import os
import sys
import json
import logging
import subprocess
from subprocess import Popen, PIPE

log = logging.getLogger()
log.setLevel(logging.DEBUG)
print('[Python] lambda handler start')

def handler(event, context):
	# convert input dictionary to string
	st = json.dumps(event)
	print('[Python] input string: [' + st + ']')

	# launch php, waiting until it completes 
	cmd = [ os.environ['LAMBDA_TASK_ROOT'] + '/bin/php', 'helloworld.php' ]
	print('[Python] lambda launching: [' + ' '.join(cmd) + ']')
	php = subprocess.run(cmd, input=st, stdout=PIPE, stderr=PIPE, check=True, encoding='utf-8')
	print('[Python] got output: [' + php.stdout + ']')
	print('[Python] got error: [' + php.stderr + ']')

	# convert php stdout back to json, and return the output dictionary
	res = json.loads(php.stdout)
	print('[Python] lambda handler finish')
	return res

