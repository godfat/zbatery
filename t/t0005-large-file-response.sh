#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"

if ! grep -v ^VmRSS: /proc/self/status >/dev/null 2>&1
then
	t_info "skipping, can't read RSS from /proc/self/status"
	exit 0
fi

t_plan 10 "large file response slurp avoidance for $model"

t_begin "setup and startup" && {
	rtmpfiles curl_out
	zbatery_setup $model 1
	# can't load Rack::Lint here since it'll cause Rev to slurp
	zbatery -E none -D large-file-response.ru -c $unicorn_config
	zbatery_wait_start
}

t_begin "read random blob sha1 and size" && {
	random_blob_sha1=$(rsha1 < random_blob)
	random_blob_size=$(wc -c < random_blob)
}

t_begin "read current RSS" && {
	curl -v http://$listen/rss
	dbgcat r_err
	rss_before=$(curl -sSfv http://$listen/rss)
	t_info "rss_before=$rss_before"
}

t_begin "send a series HTTP/1.1 requests sequentially" && {
	for i in a b c
	do
		sha1=$( (curl -sSfv http://$listen/random_blob &&
			 echo ok >$ok) | rsha1)
		test $sha1 = $random_blob_sha1
		test xok = x$(cat $ok)
	done
}

# this was a problem during development
t_begin "HTTP/1.0 test" && {
	sha1=$( (curl -0 -sSfv http://$listen/random_blob &&
	         echo ok >$ok) | rsha1)
	test $sha1 = $random_blob_sha1
	test xok = x$(cat $ok)
}

t_begin "HTTP/0.9 test" && {
	(
		printf 'GET /random_blob\r\n'
		rsha1 < $fifo > $tmp &
		wait
		echo ok > $ok
	) | socat - TCP:$listen > $fifo
	test $(cat $tmp) = $random_blob_sha1
	test xok = x$(cat $ok)
}

dbgcat r_err

t_begin "read RSS again" && {
	curl -v http://$listen/rss
	rss_after=$(curl -sSfv http://$listen/rss)
	t_info "rss_after=$rss_after"
}

t_begin "shutdown server" && {
	kill -QUIT $zbatery_pid
}

t_begin "compare RSS before and after" && {
	diff=$(( $rss_after - $rss_before ))

	# default GC malloc limit in MRI:
	fudge=$(( 8 * 1024 * 1024 ))

	t_info "test diff=$diff < orig=$random_blob_size"
	test $diff -le $(( $random_blob_size + $fudge ))
}

dbgcat r_err

t_begin "check stderr" && check_stderr

t_done
