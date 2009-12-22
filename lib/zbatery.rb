# -*- encoding: binary -*-
require 'rainbows'

module Zbatery

  # current version of Zbatery
  VERSION = "0.1.0"

  class << self

    # runs the Zbatery HttpServer with +app+ and +options+ and does
    # not return until the server has exited.
    def run(app, options = {})
      HttpServer.new(app, options).start.join
    end
  end

  Rainbows::Const::RACK_DEFAULTS["SERVER_SOFTWARE"] = "Zbatery #{VERSION}"

  # true if our Ruby implementation supports unlinked files
  UnlinkedIO = begin
    tmp = Unicorn::Util.tmpio
    tmp.chmod(0)
    tmp.close
    true
  rescue
    false
  end

  # we don't actually fork workers, but allow using the
  # {before,after}_fork hooks found in Unicorn/Rainbows!
  # config files...
  FORK_HOOK = lambda { |_,_| }

  class HttpServer < Rainbows::HttpServer

    # this class is only used to avoid breaking Unicorn user switching
    class DeadIO
      def chown(*args); end
    end

    # only used if no concurrency model is specified
    def worker_loop(worker)
      init_worker_process(worker)
      begin
        ret = IO.select(LISTENERS, nil, nil, nil) and
        ret.first.each do |sock|
          begin
            process_client(sock.accept_nonblock)
          rescue Errno::EAGAIN, Errno::ECONNABORTED
          end
        end
      rescue Errno::EINTR
      rescue Errno::EBADF, TypeError
        break
      rescue => e
        Rainbows::Error.listen_loop(e)
      end while G.alive
    end

    # no-op
    def maintain_worker_count; end

    # can't just do a graceful exit if reopening logs fails, so we just
    # continue on...
    def reopen_logs
      logger.info "reopening logs"
      Unicorn::Util.reopen_logs
      logger.info "done reopening logs"
      rescue => e
        logger.error "failed reopening logs #{e.message}"
    end

    def join
      begin
        trap(:INT) { stop(false) } # Mongrel trapped INT for Win32...

        # try these anyways regardless of platform...
        trap(:TERM) { stop(false) }
        trap(:QUIT) { stop }
        trap(:USR1) { reopen_logs }
        trap(:USR2) { reexec }

        # no other way to reliably switch concurrency models...
        trap(:HUP) { reexec; stop }

        # technically feasible in some cases, just not sanely supportable:
        %w(TTIN TTOU WINCH).each do |sig|
          trap(sig) { logger.info "SIG#{sig} is not handled by Zbatery" }
        end
      rescue => e # hopefully ignores errors on Win32...
        logger.error "failed to setup signal handler: #{e.message}"
      end
      worker = Worker.new(0, DeadIO.new)
      before_fork.call(self, worker)
      worker_loop(worker) # runs forever
    end

    def stop(graceful = true)
      Rainbows::G.quit!
      exit!(0) unless graceful
    end

    def before_fork
      hook = super
      hook == FORK_HOOK or
        logger.warn "calling before_fork without forking"
      hook
    end

    def after_fork
      hook = super
      hook == FORK_HOOK or
        logger.warn "calling after_fork without having forked"
      hook
    end
  end
end

# :stopdoc:
# override stuff we don't need or can't use portably
module Rainbows

  module Base
    # master == worker in our case
    def init_worker_process(worker)
      after_fork.call(self, worker)
      build_app! unless preload_app
      logger.info "Zbatery #@use worker_connections=#@worker_connections"
    end
  end

  # we can't/don't need to do the fchmod heartbeat Unicorn/Rainbows! does
  def G.tick
    alive
  end
end

module Unicorn

  class Configurator
    DEFAULTS[:before_fork] = DEFAULTS[:after_fork] = Zbatery::FORK_HOOK
  end

  unless Zbatery::UnlinkedIO
    require 'tempfile'
    class Util

      # Tempfiles should get automatically unlinked by GC
      def self.tmpio
        fp = Tempfile.new("zbatery")
        fp.binmode
        fp.sync = true
        fp
      end
    end
  end

end
