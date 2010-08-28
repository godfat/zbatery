# -*- encoding: binary -*-

ENV["VERSION"] or abort "VERSION= must be specified"
manifest = File.readlines('.manifest').map! { |x| x.chomp! }

# don't bother with tests that fork, not worth our time to get working
# with `gem check -t` ... (of course we care for them when testing with
# GNU make when they can run in parallel)
test_files = manifest.grep(%r{\Atest/unit/test_.*\.rb\z}).map do |f|
  File.readlines(f).grep(/\bfork\b/).empty? ? f : nil
end.compact

Gem::Specification.new do |s|
  s.name = %q{zbatery}
  s.version = ENV["VERSION"]

  s.authors = ["Zbatery hackers"]
  s.date = Time.now.utc.strftime('%Y-%m-%d')
  s.description = File.read("README").split(/\n\n/)[1]
  s.email = %q{rainbows-talk@rubyforge.org}
  s.executables = %w(zbatery)

  s.extra_rdoc_files = File.readlines('.document').map! do |x|
    x.chomp!
    if File.directory?(x)
      manifest.grep(%r{\A#{x}/})
    elsif File.file?(x)
      x
    else
      nil
    end
  end.flatten.compact

  s.files = manifest
  s.homepage = %q{http://zbatery.bogomip.org/}
  s.summary = %q{Rack HTTP server without a fork stuck in it}
  s.rdoc_options = [ "-t", "Zbatery - #{s.summary}" ]
  s.require_paths = %w(lib)
  s.rubyforge_project = %q{rainbows}

  s.test_files = test_files

  # rainbows has a boatload of optional dependencies
  # required:
  #   unicorn + rack
  # optional:
  #   revactor + rev + iobuffer
  #   rev + iobuffer
  #   eventmachine
  #   espace-neverblock + eventmachine
  #   async_sinatra + sinatra + eventmachine
  #
  # rainbows 0.91.1 depends on unicorn ~> 0.97.1, previous versions of
  # Unicorn were vulnerable to a remote DoS when exposed directly to
  # untrusted clients (a configuration only supported by Zbatery and Rainbows!,
  # Unicorn has never and will never be supported without trusted LAN clients.
  s.add_dependency(%q<rainbows>, [">= 0.97.0", "<= 1.0.0"])
  s.add_development_dependency(%q<isolate>, "~> 2.1.0")

  # s.licenses = %w(GPLv2 Ruby) # accessor not compatible with older RubyGems
end
