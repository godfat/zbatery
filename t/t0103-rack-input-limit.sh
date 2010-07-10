#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
req_curl_chunked_upload_err_check

t_plan 6 "rack.input client_max_body_size default"

t_begin "setup and startup" && {
	rtmpfiles curl_out curl_err cmbs_config
	zbatery_setup $model
	grep -v client_max_body_size < $unicorn_config > $cmbs_config
	zbatery -D sha1-random-size.ru -c $cmbs_config
	zbatery_wait_start
}

t_begin "regular request" && {
	rm -f $ok
	curl -vsSf -T random_blob -H Expect: \
	  http://$listen/ > $curl_out 2> $curl_err || > $ok
	dbgcat curl_err
	dbgcat curl_out
	test -e $ok
}

t_begin "chunked request" && {
	rm -f $ok
	curl -vsSf -T- < random_blob -H Expect: \
	  http://$listen/ > $curl_out 2> $curl_err || > $ok
	dbgcat curl_err
	dbgcat curl_out
	test -e $ok
}

t_begin "default size sha1 chunked" && {
	blob_sha1=3b71f43ff30f4b15b5cd85dd9e95ebc7e84eb5a3
	rm -f $ok
	> $r_err
	dd if=/dev/zero bs=1048576 count=1 | \
	  curl -vsSf -T- -H Expect: \
	  http://$listen/ > $curl_out 2> $curl_err
	test "$(cat $curl_out)" = $blob_sha1
	dbgcat curl_err
	dbgcat curl_out
}

t_begin "default size sha1 content-length" && {
	blob_sha1=3b71f43ff30f4b15b5cd85dd9e95ebc7e84eb5a3
	rm -f $ok
	dd if=/dev/zero bs=1048576 count=1 of=$tmp
	curl -vsSf -T $tmp -H Expect: \
	  http://$listen/ > $curl_out 2> $curl_err
	test "$(cat $curl_out)" = $blob_sha1
	dbgcat curl_err
	dbgcat curl_out
}

t_begin "shutdown" && {
	kill $zbatery_pid
}

t_done
