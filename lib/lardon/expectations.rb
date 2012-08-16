class Lardon
  class Should
    def initialize(this)
      @this = this
    end
  end
end

class Object
  def should(*arguments, &block)
    Lardon::Should.new(self).be(*args, &block)
  end
end