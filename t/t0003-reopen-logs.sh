#!/bin/sh
# don't set nr_client for Rev, only _one_ app running at once :x
nr_client=${nr_client-2}
. ./test-lib.sh

t_plan 19 "reopen rotated logs"

t_begin "setup and startup" && {
	rtmpfiles curl_out curl_err r_rot
	zbatery_setup $model
	zbatery -D sleep.ru -c $unicorn_config
	zbatery_wait_start
}

t_begin "ensure server is responsive" && {
	curl -sSf http://$listen/ >/dev/null
}

t_begin "start $nr_client concurrent requests" && {
	start=$(date +%s)
	for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
	do
		( curl -sSf http://$listen/2 >> $curl_out 2>> $curl_err ) &
	done
}

t_begin "ensure stderr log is clean" && check_stderr

t_begin "external log rotation" && {
	rm -f $r_rot
	mv $r_err $r_rot
}

t_begin "send reopen log signal (USR1)" && {
	kill -USR1 $zbatery_pid
}

t_begin "wait for rotated log to reappear" && {
	nr=60
	while ! test -f $r_err && test $nr -ge 0
	do
		sleep 1
		nr=$(( $nr - 1 ))
	done
}

t_begin "wait to reopen logs" && {
	nr=60
	re="done reopening logs"
	while ! grep "$re" < $r_err >/dev/null && test $nr -ge 0
	do
		sleep 1
		nr=$(( $nr - 1 ))
	done
}

dbgcat r_rot
dbgcat r_err

t_begin "wait curl requests to finish" && {
	wait
	t_info elapsed=$(( $(date +%s) - $start ))
}

t_begin "ensure no errors from curl" && {
	test ! -s $curl_err
}

t_begin "curl got $nr_client responses" && {
	test "$(wc -l < $curl_out)" -eq $nr_client
}

t_begin "all responses were identical" && {
	nr=$(sort < $curl_out | uniq | wc -l)
	test "$nr" -eq 1
}

t_begin 'response was "Hello"' && {
	test x$(sort < $curl_out | uniq) = xHello
}

t_begin "current server stderr is clean" && check_stderr

t_begin "rotated stderr is clean" && {
	check_stderr $r_rot
}

t_begin "server is now writing logs to new stderr" && {
	before_rot=$(wc -c < $r_rot)
	before_err=$(wc -c < $r_err)
	curl -sSfv http://$listen/
	after_rot=$(wc -c < $r_rot)
	after_err=$(wc -c < $r_err)
	test $after_rot -eq $before_rot
	test $after_err -gt $before_err
}

t_begin "stop server" && {
	kill $zbatery_pid
}

dbgcat r_err

t_begin "current server stderr is clean" && check_stderr
t_begin "rotated stderr is clean" && check_stderr $r_rot

t_done
