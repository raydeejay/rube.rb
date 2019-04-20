require 'singleton'
require_relative 'AttrBoolean'

module Parts
  class Part
    include AttrBoolean

    # every concrete part should add itself to this array
    @@parts = []
    def self.parts
      @@parts
    end

    def self.register_into_parts
      puts "Registering #{self}"
      @@parts << self
    end

    attr_boolean_reader :crate, :transparent, :empty
    attr_reader :char, :category

    # this method, and the private ones below, define a DSL for
    # defining new Parts
    def self.define(name, &block)
      klass = Class.new(self) do
        define_method(:initialize) do
          @empty = false
          @crate = nil
          @transparent = false
          @char = nil
          @category = nil
          instance_eval(&block)
        end
      end

      ::Parts.const_set("#{name}", klass)
    end

    # this method makes CodeGridPositions and Parts polymorphic
    def part
      self
    end

    def action(x, y)
      @action.call(x,y) if @action
    end

    private
    def register!
      self.class.register
    end

    def char!(char)
      @char = char
    end

    def crate!
      @crate = self
    end

    def transparent!
      @transparent = true
    end

    def empty!
      @empty = true
    end

    def category!(number)
      @category = number
    end

    def action!(&block)
      @action = block
    end

  end

  class SingletonPart < Part
    # subclasses of SingletonPart can call `register!` in their definition
    # to be eligible on grid loading
    include Singleton

    def self.register(name, &block)
      self.define(name, &block).register_into_parts
    end
  end
end
