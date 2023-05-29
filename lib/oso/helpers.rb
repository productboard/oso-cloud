module OsoCloud
  # @!visibility private
  module Helpers
    # @!visibility private
    def self.extract_value(x)
      return OsoCloud::Core::Value.new(type: 'String', id: x) if x.is_a? String

      return OsoCloud::Core::Value.new(type: nil, id: nil) if x.nil?

      type = (x.type.nil? ? nil : x.type.to_s)
      id = (x.id.nil? ? nil : x.id.to_s)
      OsoCloud::Core::Value.new(type: type, id: id)
    end

    # @!visibility private
    def self.extract_arg_query(x)
      extract_value(x)
    end

    # @!visibility private
    def self.param_to_fact(predicate, args)
      OsoCloud::Core::Fact.new(predicate: predicate, args: args.map { |a| extract_value(a) })
    end

    # @!visibility private
    def self.params_to_facts(facts)
      facts.map { |predicate, *args| param_to_fact(predicate, args) }
    end

    # @!visibility private
    def self.facts_to_params(facts)
      facts.map do |f|
        name = f.predicate
        args = f.args.map do |a|
          v = from_value(a)
          if v.is_a? Hash
            OsoCloud::Value.new(type: v[:type], id: v[:id])
          else
            v
          end
        end
        [name, *args]
      end
    end

    def self.from_value(value)
      if value.id.nil?
        if value.type.nil?
          nil
        else
          { type: value.type }
        end
      elsif value.type == 'String'
        value.id
      else
        { id: value.id, type: value.type }
      end
    end

    # @!visibility private
    def self.to_hash(o)
      return o.map { |v| to_hash(v) } if o.is_a? Array
      return o if o.instance_variables.empty?

      hash = {}
      o.instance_variables.each do |var|
        v = var.to_s.delete('@')
        value = o.send(v)
        hash[v] = to_hash(value)
      end
      hash
    end
  end
end
