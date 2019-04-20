module AttrBoolean
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def attr_boolean(*names)
      attr_boolean_writer(*names)
      attr_boolean_reader(*names)
    end
    # new implementation returning the value or nil
    def attr_boolean_reader(*names)
      names.each do |name|
        define_method(:"#{name}?") do
          it = instance_variable_get(:"@#{name}")
          it ? it : nil
        end
      end
    end
    # original implementation returning booleans

    #   def attr_boolean_reader(*names)
    #     names.each do |name|
    #       define_method(:"#{name}?") do
    #         !!instance_variable_get(:"@#{name}")
    #       end
    #     end
    #   end
    def attr_boolean_writer(*names)
      define_method(:"#{name}=") do |value|
        instance_variable_set(:"@#{name}", value)
      end
    end
  end

end
