class Peck
  class Should
    # Kills ==, ===, =~, eql?, equal?, frozen?, instance_of?, is_a?,
    # kind_of?, nil?, respond_to?, tainted?
    KILL_METHODS_RE = /\?|^\W+$/
    instance_methods.each do |name|
      undef_method(name) if name =~ KILL_METHODS_RE
    end

    def initialize(this)
      @this = this
      @negated = false
      Thread.current['peck-spec'].expectations << self
    end

    def be(*args, &block)
      if args.empty?
        self
      else
        block = args.shift unless block_given?
        satisfy(*args, &block)
      end
    end

    def satisfy(*args, &block)
      if args.size == 1 && String === args.first
        description = args.shift
      else
        description = ""
      end

      result = yield(@this, *args)
      unless @negated ^ result
        raise Peck::Error.new(:failed, description)
      end
      result
    end

    PREDICATE_METHOD_RE = /\w[^?]\z/
    def method_missing(name, *args, &block)
      name = "#{name}?" if name.to_s =~ PREDICATE_METHOD_RE

      desc = @negated ? "not " : ""
      desc << @this.inspect << "." << name.to_s
      desc << "(" << args.map{|x|x.inspect}.join(", ") << ") failed"

      satisfy(desc) { |x| x.__send__(name, *args, &block) }
    end
  end
end

class Object
  def should(*args, &block)
    Peck::Should.new(self).be(*args, &block)
  end
end