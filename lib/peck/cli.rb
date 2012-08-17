# encoding: utf-8

class Peck
  # Parser for command line options
  class OptionParser
    # Parses ARGV from a Ruby script and returns options as a hash and
    # arguments as a list.
    #
    #   OptionParser.parse(%w(create --username manfred)) #=>
    #     [{"username"=>"manfred"}, ["create"]]
    def self.parse(argv)
      return [{},[]] if argv.empty?

      options  = {}
      rest     = []
      switch   = nil

      for value in argv
        bytes = value.respond_to?(:bytes) ? value.bytes.first(2) : [value[0], value[1]]
        # value is a switch
        if bytes[0] == 45
          switch = value.slice((bytes[1] == 45 ? 2 : 1)..-1)
          options[switch] = nil
        else
          if switch
            # we encountered another switch so this
            # value belongs to the last switch
            options[switch] = value
            switch = nil
          else
            rest << value
          end
        end
      end

      [options, rest]
    end
  end

  class CLI
    attr_reader :peck, :path, :one_by_one
    alias one_by_one? one_by_one
    
    def initialize(peck, argv)
      @peck = peck

      @options, @argv = Peck::OptionParser.parse(argv.dup)
      @options.each do |switch, value|
        case switch
        when 'one-by-one'
          @one_by_one = true
          @path = value
        end
      end

      @path ||= @argv[0]
    end

    def find_spec_files
      files = []
      Dir.glob(File.join(Dir.pwd, path, '**/*_spec.rb')) do |filename|
        files << filename
      end; files
    end

    SPEC_FILE_RE = /_spec\.rb\Z/

    def spec_files
      unless path =~ SPEC_FILE_RE
        find_spec_files
      else
        [path]
      end
    end

    def load_specs
      spec_files.each do |filename|
        load filename
      end
    end

    def iterate_specs
      spec_files.each do |filename|
        command = "#{peck} #{filename}"
        system(command)
      end
    end

    def run
      if one_by_one?
        $stdout.sync = true
        iterate_specs
      else
        load_specs
        Peck.run_at_exit
      end
    end

    def self.run(peck, argv)
      cli = new(peck, argv)
      cli.run
      cli
    end
  end
end