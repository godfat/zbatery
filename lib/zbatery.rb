# -*- encoding: binary -*-
# :enddoc:
require 'rainbows'
Rainbows.forked = true
module Zbatery

  VERSION = "4.0.0"

  Rainbows::Const::RACK_DEFAULTS["SERVER_SOFTWARE"] = "Zbatery #{VERSION}"

  # we don't actually fork workers, but allow using the
  # {before,after}_fork hooks found in Unicorn/Rainbows!
  # config files...
  FORK_HOOK = lambda { |_,_| }
end

# :stopdoc:
# override stuff we don't need or can't use portably
module Rainbows

  module Base
    # master == worker in our case
    def init_worker_process(worker)
      after_fork.call(self, worker)
      worker.user(*user) if user.kind_of?(Array) && ! worker.switched
      build_app! unless preload_app
      Rainbows::Response.setup
      Rainbows::MaxBody.setup
      Rainbows::ProcessClient.const_set(:APP, @app)

      logger.info "Zbatery #@use worker_connections=#@worker_connections"
    end
  end

  # we can't/don't need to do the fchmod heartbeat Unicorn/Rainbows! does
  def self.tick
    alive
  end

  class HttpServer

    # only used if no concurrency model is specified
    def worker_loop(worker)
      init_worker_process(worker)
      begin
        ret = IO.select(LISTENERS, nil, nil, nil) and
        ret[0].each do |sock|
          io = sock.kgio_tryaccept and process_client(io)
        end
      rescue Errno::EINTR
      rescue Errno::EBADF, TypeError
        break
      rescue => e
        Rainbows::Error.listen_loop(e)
      end while Rainbows.alive
    end

    # no-op
    def maintain_worker_count; end
    def spawn_missing_workers; end
    def init_self_pipe!; end

    # can't just do a graceful exit if reopening logs fails, so we just
    # continue on...
    def reopen_logs
      logger.info "reopening logs"
      Unicorn::Util.reopen_logs
      logger.info "done reopening logs"
      rescue => e
        logger.error "failed reopening logs #{e.message}"
    end

    def trap_deferred(sig)
      # nothing
    end

    def join
      trap(:INT) { stop(false) }
      trap(:TERM) { stop(false) }
      trap(:QUIT) { stop }
      trap(:USR1) { reopen_logs }
      trap(:USR2) { reexec }
      trap(:HUP) { reexec; stop }

      # technically feasible in some cases, just not sanely supportable:
      %w(TTIN TTOU WINCH).each do |sig|
        trap(sig) { logger.info "SIG#{sig} is not handled by Zbatery" }
      end

      if ready_pipe
        ready_pipe.syswrite($$.to_s)
        ready_pipe.close
        self.ready_pipe = nil
      end
      extend(Rainbows.const_get(@use))
      worker = Worker.new(0)
      before_fork.call(self, worker)
      worker_loop(worker) # runs forever
    end

    def stop(graceful = true)
      Rainbows.quit!
      exit!(0) unless graceful
    end

    def before_fork
      hook = super
      hook == Zbatery::FORK_HOOK or
        logger.warn "calling before_fork without forking"
      hook
    end

    def after_fork
      hook = super
      hook == Zbatery::FORK_HOOK or
        logger.warn "calling after_fork without having forked"
      hook
    end
  end
end

Unicorn::Configurator::DEFAULTS[:before_fork] =
  Unicorn::Configurator::DEFAULTS[:after_fork] = Zbatery::FORK_HOOK
