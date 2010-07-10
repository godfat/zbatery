#!/bin/sh
# Copyright (c) 2009 Rainbows! developers
. ./my-tap-lib.sh

set +u

# sometimes we rely on http_proxy to avoid wasting bandwidth with Isolate
# and multiple Ruby versions
NO_PROXY=${UNICORN_TEST_ADDR-127.0.0.1}
export NO_PROXY

if test -z "$model"
then
	# defaulting to Base would unfortunately fail some concurrency tests
	model=ThreadSpawn
	t_info "model undefined, defaulting to $model"
fi

set -e
RUBY="${RUBY-ruby}"
RUBY_VERSION=${RUBY_VERSION-$($RUBY -e 'puts RUBY_VERSION')}
t_pfx=$PWD/trash/$model.$T-$RUBY_ENGINE-$RUBY_VERSION
set -u

PATH=$PWD/bin:$PATH
export PATH

test -x $PWD/bin/unused_listen || die "must be run in 't' directory"

# requires $1 and prints out the value of $2
require_check () {
	lib=$1
	const=$2
	if ! $RUBY -r$lib -e "puts $const" >/dev/null 2>&1
	then
		t_info "skipping $T since we don't have $lib"
		exit 0
	fi
}

skip_models () {
	for i in "$@"
	do
		if test x"$model" != x"$i"
		then
			continue
		fi
		t_info "skipping $T since it is not compatible with $model"
		exit 0
	done
}


# given a list of variable names, create temporary files and assign
# the pathnames to those variables
rtmpfiles () {
	for id in "$@"
	do
		name=$id
		_tmp=$t_pfx.$id
		eval "$id=$_tmp"

		case $name in
		*fifo)
			rm -f $_tmp
			mkfifo $_tmp
			T_RM_LIST="$T_RM_LIST $_tmp"
			;;
		*socket)
			rm -f $_tmp
			T_RM_LIST="$T_RM_LIST $_tmp"
			;;
		*)
			> $_tmp
			T_OK_RM_LIST="$T_OK_RM_LIST $_tmp"
			;;
		esac
	done
}

dbgcat () {
	id=$1
	eval '_file=$'$id
	echo "==> $id <=="
	sed -e "s/^/$id:/" < $_file
}

check_stderr () {
	set +u
	_r_err=${1-${r_err}}
	set -u
	if grep -i Error $_r_err
	then
		die "Errors found in $_r_err"
	elif grep SIGKILL $_r_err
	then
		die "SIGKILL found in $_r_err"
	fi
}

# zbatery_setup [ MODEL [ WORKER_CONNECTIONS ] ]
zbatery_setup () {
	eval $(unused_listen)
	rtmpfiles unicorn_config pid r_err r_out fifo tmp ok
	cat > $unicorn_config <<EOF
listen "$listen"
pid "$pid"
stderr_path "$r_err"
stdout_path "$r_out"

after_fork do |server, worker|
  # test script will block while reading from $fifo,
  # so notify the script on the first worker we spawn
  # by opening the FIFO
  if worker.nr == 0
    File.open("$fifo", "wb") { |fp| fp.syswrite "START" }
  end
end
EOF
	{
		# set a higher default for tests since we run heavily-loaded
		# boxes and sometimes sleep 1s in tests
		kato=5
		echo 'Rainbows! do'
		echo "  client_max_body_size nil"
		if test $# -ge 1
		then
			echo "  use :$1"
			test $# -eq 2 && echo "  worker_connections $2"
			if test $# -eq 3
			then
				echo "  keepalive_timeout $3"
			else
				echo "  keepalive_timeout $kato"
			fi
		else
			echo "  use :$model"
			echo "  keepalive_timeout $kato"
		fi
		echo end
	} >> $unicorn_config
}

zbatery_wait_start () {
	# "cat $fifo" will block until the before_fork hook is called in
	# the Unicorn config file
	test xSTART = x"$(cat $fifo)"
	zbatery_pid=$(cat $pid)
}

rsha1 () {
	_cmd="$(which sha1sum 2>/dev/null || :)"
	test -n "$_cmd" || _cmd="$(which openssl 2>/dev/null || :) sha1"
	test "$_cmd" != " sha1" || _cmd="$(which gsha1sum 2>/dev/null || :)"

	# last resort, see comments in sha1sum.rb for reasoning
	test -n "$_cmd" || _cmd=sha1sum.rb
	expr "$($_cmd)" : '\([a-f0-9]\{40\}\)'
}

req_curl_chunked_upload_err_check () {
	set +e
	curl --version 2>/dev/null | awk '$1 == "curl" {
		split($2, v, /\./)
		if ((v[1] < 7) || (v[1] == 7 && v[2] < 18))
			code = 1
	}
	END { exit(code) }'
	if test $? -ne 0
	then
		t_info "curl >= 7.18.0 required for $T"
		exit 0
	fi
}

case $model in
Rev) require_check rev Rev::VERSION ;;
Revactor) require_check revactor Revactor::VERSION ;;
EventMachine) require_check eventmachine EventMachine::VERSION ;;
esac
