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
	zbatery_setup $model
	# can't load Rack::Lint here since it'll cause Rev to slurp
	zbatery -E none -D large-file-response.ru -c $unicorn_config
	zbatery_wait_start
}

t_begin "read random blob size" && {
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
		size=$( (curl -sSfv http://$listen/random_blob &&
			 echo ok >$ok) |wc -c)
		test $size -eq $random_blob_size
		test xok = x$(cat $ok)
	done
}

# this was a problem during development
t_begin "HTTP/1.0 test" && {
	size=$( (curl -0 -sSfv http://$listen/random_blob &&
	         echo ok >$ok) |wc -c)
	test $size -eq $random_blob_size
	test xok = x$(cat $ok)
}

t_begin "HTTP/0.9 test" && {
	(
		printf 'GET /random_blob\r\n'
		cat $fifo > $tmp &
		wait
		echo ok > $ok
	) | socat - TCP:$listen > $fifo
	cmp $tmp random_blob
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
	t_info "test diff=$diff < orig=$random_blob_size"
	test $diff -le $random_blob_size
}

dbgcat r_err

t_begin "check stderr" && check_stderr

t_done
