# SHA1 checksum generator
require 'digest/sha1'
use Rack::ContentLength
cap = 16384
app = lambda do |env|
  /\A100-continue\z/i =~ env['HTTP_EXPECT'] and
    return [ 100, {}, [] ]
  digest = Digest::SHA1.new
  input = env['rack.input']
  if buf = input.read(rand(cap))
    begin
      raise "#{buf.size} > #{cap}" if buf.size > cap
      digest.update(buf)
    end while input.read(rand(cap), buf)
  end

  [ 200, {'Content-Type' => 'text/plain'}, [ digest.hexdigest << "\n" ] ]
end
run app
