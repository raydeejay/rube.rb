module AttrBoolean
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def attr_boolean(*names)
      names.each do |name|
        define_method(:"#{name}=") do |value|
          instance_variable_set(:"@#{name}", value)
        end

        define_method(:"#{name}?") do
          !!instance_variable_get(:"@#{name}")
        end
      end
    end
  end
end
