#\ -E none
use Rack::ContentLength
use Rack::ContentType, "text/plain"
run lambda { |env|
  rv = case env["PATH_INFO"]
  when "/backtick"
    `printf 'hi'`
  when "/system"
    rv = system("true")
    rv.to_s
  when "/fork_ignore"
    pid = fork {}
    pid.class.to_s
  when "/fork_wait"
    _, status = Process.waitpid2(fork {})
    status.success?.to_s
  when "/popen"
    io = IO.popen('echo popen')
    io.read
  end
  [ 200, {}, [ rv ] ]
}
