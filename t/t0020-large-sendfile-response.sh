#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
case $RUBY_ENGINE in
ruby) ;;
*)
	t_info "skipping $T since it can't load the sendfile gem, yet"
	exit 0
	;;
esac

t_plan 12 "large sendfile response for $model"

t_begin "setup and startup" && {
	rtmpfiles curl_out a b c slow_a slow_b
	zbatery_setup $model
	echo 'require "sendfile"' >> $unicorn_config
	echo 'def (::IO).copy_stream(*x); abort "NO"; end' >> $unicorn_config

	# can't load Rack::Lint here since it clobbers body#to_path
	zbatery -E none -D large-file-response.ru -c $unicorn_config
	zbatery_wait_start
}

t_begin "read random blob sha1" && {
	random_blob_sha1=$(rsha1 < random_blob)
	three_sha1=$(cat random_blob random_blob random_blob | rsha1)
}

t_begin "send keepalive HTTP/1.1 requests in parallel" && {
	for i in $a $b $c $slow_a $slow_b
	do
		curl -sSf http://$listen/random_blob \
		          http://$listen/random_blob \
		          http://$listen/random_blob | rsha1 > $i &
	done
	wait
	for i in $a $b $c $slow_a $slow_b
	do
		test x$(cat $i) = x$three_sha1
	done
}

t_begin "send a batch of abortive HTTP/1.1 requests in parallel" && {
	for i in $a $b $c $slow_a $slow_b
	do
		rm -f $i
		(
			curl -sSf --max-time 5 --limit-rate 1K \
			  http://$listen/random_blob >/dev/null || echo ok > $i
		) &
	done
	wait
}

t_begin "all requests timed out" && {
	for i in $a $b $c $slow_a $slow_b
	do
		test x$(cat $i) = xok
	done
}

s='$NF ~ /worker_connections=[0-9]+/{gsub(/[^0-9]/,"",$3); print $3; exit}'
t_begin "check proc to ensure file is closed properly (Linux only)" && {
	worker_pid=$(awk "$s" < $r_err)
	test -n "$worker_pid"
	if test -d /proc/$worker_pid/fd
	then
		if ls -l /proc/$worker_pid/fd | grep random_blob
		then
			t_info "random_blob file is open ($model)"
		fi
	else
		t_info "/proc/$worker_pid/fd not found"
	fi
}

t_begin "send a bunch of HTTP/1.1 requests in parallel" && {
	(
		curl -sSf --limit-rate 1M http://$listen/random_blob | \
		  rsha1 > $slow_a
	) &
	(
		curl -sSf --limit-rate 750K http://$listen/random_blob | \
		  rsha1 > $slow_b
	) &
	for i in $a $b $c
	do
		(
			curl -sSf http://$listen/random_blob | rsha1 > $i
		) &
	done
	wait
	for i in $a $b $c $slow_a $slow_b
	do
		test x$(cat $i) = x$random_blob_sha1
	done
}

# this was a problem during development
t_begin "HTTP/1.0 test" && {
	sha1=$( (curl -0 -sSf http://$listen/random_blob &&
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

t_begin "check proc to ensure file is closed properly (Linux only)" && {
	worker_pid=$(awk "$s" < $r_err)
	test -n "$worker_pid"
	if test -d /proc/$worker_pid/fd
	then
		if ls -l /proc/$worker_pid/fd | grep random_blob
		then
			t_info "random_blob file is open ($model)"
		fi
	else
		t_info "/proc/$worker_pid/fd not found"
	fi
}

t_begin "shutdown server" && {
	kill -QUIT $zbatery_pid
}

dbgcat r_err

t_begin "check stderr" && check_stderr

t_done
