# encoding: utf-8

require 'peck/notifiers/base'

class Peck
  class Notifiers
    class Documentation < Peck::Notifiers::Base
      def initialize
        @started_at = @finished_at = Time.now
        @last_context_label = nil
      end

      def started
        @started_at = Time.now
      end

      def finished
        @finished_at = Time.now
      end

      def finished_specification(spec)
        unless spec.context.label == @last_context_label
          @last_context_label = spec.context.label
          $stdout.puts
          $stdout.puts(spec.context.label)
          $stdout.puts
        end
        if spec.passed?
          $stdout.write(" [\033[32mx\033[0m] ")
        elsif spec.failed?
          $stdout.write(" \033[97;101m[!]\033[0m ")
        end
        $stdout.puts(spec.description)
      end

      def write_exeception(number, event)
        puts "  \033[31m#{number}) #{event.spec.label}\033[0m\n\n"
        backtrace = clean_backtrace(event.exception.backtrace)

        parts = []
        unless event.exception.message.nil? || event.exception.message == ''
          parts << "  #{event.exception.message}"
        end
        parts << "\t#{backtrace.join("\n\t")}"
        parts << nil
        puts parts.join("\n\n")
      end
      
      def write_event(number, event)
        case event.exception
        when Exception
          write_exeception(number, event)
        else
          raise ArgumentError, "Don't know how to display event `#{event.expectation.class.name}'"
        end
      end

      def write_events
        Peck.all_events.each_with_index do |event, index|
          number = index + 1
          write_event(number, event)
        end
      end

      def runtime_in_seconds
        runtime = @finished_at - @started_at
        (runtime * 100).round / 100.0
      end

      def write_stats
        puts "#{Peck.counter.ran} #{pluralize(Peck.counter.ran, 'spec')}, #{Peck.counter.failed} #{pluralize(Peck.counter.failed, 'failure')}, finished in #{runtime_in_seconds} seconds."
      end

      def write
        puts if Peck.counter.ran > 0
        write_stats
        puts
        write_events
      end

      def install_at_exit
        at_exit { write }
      end
    end
  end
end