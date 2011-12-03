#!/bin/sh
. ./test-lib.sh

# FIXME: fork + Fibers segfaults: https://redmine.ruby-lang.org/issues/5700
skip_models NeverBlock FiberSpawn FiberPool CoolioFiberSpawn

t_plan 8 "SIGCHLD handling for $model"

t_begin "setup and startup" && {
	rtmpfiles curl_out
	zbatery_setup $model
	zbatery -D sigchld.ru -c $unicorn_config
	zbatery_wait_start
}

t_begin "backtick" && {
	test xhi = x"$(curl -sSf http://$listen/backtick)"
}

t_begin "system" && {
	test xtrue = x"$(curl -sSf http://$listen/system)"
}

t_begin "fork_ignore" && {
	test xFixnum = x"$(curl -sSf http://$listen/fork_ignore)"
}

t_begin "fork_wait" && {
	test xtrue = x"$(curl -sSf http://$listen/fork_wait)"
}

t_begin "popen" && {
	test xpopen = x"$(curl -sSf http://$listen/popen)"
}

t_begin "shutdown server" && {
	kill -QUIT $zbatery_pid
}

dbgcat r_err

t_begin "check stderr" && check_stderr

t_done
