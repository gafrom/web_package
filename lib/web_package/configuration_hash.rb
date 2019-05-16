module WebPackage
  # A Hash class with configurable dot-methods (accessors).
  class ConfigurationHash < Hash
    def initialize(accessor_names, &block)
      self.accessors = [*accessor_names]
      super(&block)
    end

    def accessors=(method_names)
      self.class.class_eval do
        method_names.map(&:to_sym).each do |method_name|
          define_method(method_name) { self[method_name] }
          define_method("#{method_name}=") { |value| self[method_name] = value }
        end
      end
    end
  end
end
