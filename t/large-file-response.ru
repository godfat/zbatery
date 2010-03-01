# lib-large-file-response will stop running if we're not on Linux here
use Rack::ContentLength
use Rack::ContentType
map "/rss" do
  run lambda { |env|
    # on Linux, this is in kilobytes
    GC.start if GC.respond_to?(:start)
    ::File.read("/proc/self/status") =~ /^VmRSS:\s+(\d+)/
    [ 200, {}, [ ($1.to_i * 1024).to_s ] ]
  }
end
map "/" do
  run Rack::File.new(Dir.pwd)
end
