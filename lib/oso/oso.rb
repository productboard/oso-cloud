require 'json'
require 'net/http'
require 'uri'

require 'oso/version'
require 'oso/api'
require 'oso/helpers'

##
# For more detailed documentation, see
# https://www.osohq.com/docs/reference/client-apis/ruby
module OsoCloud
  # Represents an object in your application, with a type and id.
  # Both "type" and "id" should be strings.
  Value = Struct.new(:type, :id, keyword_init: true) do
    def to_api_value
      OsoCloud::Helpers.extract_value(self)
    end
  end

  # Oso Cloud client for Ruby
  #
  # About facts:
  #
  # Some of these methods accept and return "fact"s.
  # A "fact" is an array with at least one element.
  # The first element must be a string, representing the fact's name.
  # Any other elements in the array, which together represent the fact's arguments,
  # can be "OsoCloud::Value" objects or strings.
  class Oso
    def initialize(url: 'https://cloud.osohq.com', api_key: nil)
      @api = OsoCloud::Core::Api.new(url: url, api_key: api_key)
    end

    ##
    # Update the active policy
    #
    # Updates the active policy in Oso Cloud, The string passed into
    # this method should be written in Polar.
    #
    # @param policy [String]
    # @return [nil]
    def policy(policy)
      @api.post_policy(OsoCloud::Core::Policy.new(src: policy, filename: ''))
      nil
    end

    ##
    # Check a permission
    #
    # Returns true if the actor can perform the action on the resource;
    # otherwise false.
    #
    # @param actor [OsoCloud::Value]
    # @param action [String]
    # @param resource [OsoCloud::Value]
    # @param context_facts [Array<fact>]
    # @return [Boolean]
    # @see Oso for more information about facts
    def authorize(actor, action, resource, context_facts = [])
      actor_typed_id = actor.to_api_value
      resource_typed_id = resource.to_api_value
      result = @api.post_authorize(OsoCloud::Core::AuthorizeQuery.new(
                                     actor_type: actor_typed_id.type,
                                     actor_id: actor_typed_id.id,
                                     action: action,
                                     resource_type: resource_typed_id.type,
                                     resource_id: resource_typed_id.id,
                                     context_facts: OsoCloud::Helpers.params_to_facts(context_facts)
                                   ))
      result.allowed
    end

    ##
    # Check authorized resources
    #
    # Returns a subset of the resource which an actor can perform
    # a particular action. Ordering and duplicates, if any exist, are preserved.
    #
    # @param actor [OsoCloud::Value]
    # @param action [String]
    # @param resources [Array<OsoCloud::Value>]
    # @param context_facts [Array<fact>]
    # @return [Array<OsoCloud::Value>]
    # @see Oso for more information about facts
    def authorize_resources(actor, action, resources, context_facts = [])
      return [] if resources.nil?
      return [] if resources.empty?

      key = lambda do |type, id|
        "#{type}:#{id}"
      end

      resources_extracted = resources.map(&:to_api_value)
      actor_typed_id = actor.to_api_value
      data = OsoCloud::Core::AuthorizeResourcesQuery.new(
        actor_type: actor_typed_id.type, actor_id: actor_typed_id.id,
        action: action,
        resources: resources_extracted,
        context_facts: OsoCloud::Helpers.params_to_facts(context_facts)
      )
      result = @api.post_authorize_resources(data)

      return [] if result.results.empty?

      results_lookup = {}
      result.results.each do |r|
        k = key.call(r.type, r.id)
        results_lookup[k] = true if results_lookup[k].nil?
      end

      resources.select do |r|
        e = r.to_api_value
        exists = results_lookup[key.call(e.type, e.id)]
        exists
      end
    end

    ##
    # List authorized resources
    #
    # Fetches a list of resource ids on which an actor can perform a
    # particular action.
    #
    # @param actor [OsoCloud::Value]
    # @param action [String]
    # @param resource_type [String]
    # @param context_facts [Array<fact>]
    # @return [Array<String>]
    # @see Oso for more information about facts
    def list(actor, action, resource_type, context_facts = [])
      actor_typed_id = actor.to_api_value
      result = @api.post_list(OsoCloud::Core::ListQuery.new(
                                actor_type: actor_typed_id.type,
                                actor_id: actor_typed_id.id,
                                action: action,
                                resource_type: resource_type,
                                context_facts: OsoCloud::Helpers.params_to_facts(context_facts)
                              ))
      result.results
    end

    ##
    # List authorized actions
    #
    # Fetches a list of actions which an actor can perform on a particular resource.
    #
    # @param actor [OsoCloud::Value]
    # @param resource [OsoCloud::Value]
    # @param context_facts [Array<fact>]
    # @return [Array<String>]
    # @see Oso for more information about facts
    def actions(actor, resource, context_facts = [])
      actor_typed_id = actor.to_api_value
      resource_typed_id = resource.to_api_value
      result = @api.post_actions(OsoCloud::Core::ActionsQuery.new(
                                   actor_type: actor_typed_id.type,
                                   actor_id: actor_typed_id.id,
                                   resource_type: resource_typed_id.type,
                                   resource_id: resource_typed_id.id,
                                   context_facts: OsoCloud::Helpers.params_to_facts(context_facts)
                                 ))
      result.results
    end

    ##
    # Add a fact
    #
    # Adds a fact with the given name and arguments.
    #
    # @param name [String]
    # @param args [*[String, OsoCloud::Value]]
    # @return [nil]
    def tell(name, *args)
      typed_args = args.map { |a| OsoCloud::Helpers.extract_value(a) }
      @api.post_facts(OsoCloud::Core::Fact.new(predicate: name, args: typed_args))
      nil
    end

    ##
    # Add many facts
    #
    # Adds many facts at once.
    #
    # @param facts [Array<fact>]
    # @return [nil]
    # @see Oso for more information about facts
    def bulk_tell(facts)
      @api.post_bulk_load(OsoCloud::Helpers.params_to_facts(facts))
      nil
    end

    ##
    # Delete fact
    #
    # Deletes a fact. Does not throw an error if the fact is not found.
    #
    # @param name [String]
    # @param args [*[String, OsoCloud::Value]]
    # @return [nil]
    def delete(name, *args)
      typed_args = args.map { |a| OsoCloud::Helpers.extract_value(a) }
      @api.delete_facts(OsoCloud::Core::Fact.new(predicate: name, args: typed_args))
      nil
    end

    ##
    # Delete many facts
    #
    # Deletes many facts at once. Does not throw an error when some of
    # the facts are not found.
    #
    # @param facts [Array<fact>]
    # @return [nil]
    # @see Oso for more information about facts
    def bulk_delete(facts)
      @api.post_bulk_delete(OsoCloud::Helpers.params_to_facts(facts))
      nil
    end

    ##
    # Transactionally delete and insert fact(s)
    #
    # Delete(s) are processed before insertion(s). nil arguments in facts to be
    # deleted act as wildcards. Does not throw an error if facts to be deleted
    # are not found or facts to be inserted already exist.
    #
    #
    # Throws an OsoCloud::Core::Api exception if error returned from server.
    #
    # @param delete [Array<fact>]
    # @param insert [Array<fact>]
    # @return [nil]
    # @see Oso for more information about facts
    def bulk(delete: [], insert: [])
      @api.post_bulk(OsoCloud::Core::Bulk.new(delete: OsoCloud::Helpers.params_to_facts(delete),
                                              tell: OsoCloud::Helpers.params_to_facts(insert)))
      nil
    end

    ##
    # List facts
    #
    # Lists facts that are stored in Oso Cloud. Can be used to check the existence
    # of a particular fact, or used to fetch all facts that have a particular
    # argument. nil arguments operate as wildcards.
    #
    # @param name [String]
    # @param args [*[String, OsoCloud::Value, nil]]
    # @return [Array<fact>]
    # @see Oso for more information about facts
    def get(name, *args)
      OsoCloud::Helpers.facts_to_params(@api.get_facts(name, args))
    end

    ##
    # List added and derived facts
    #
    # Lists facts that are stored in Oso Cloud in addition to derived facts
    # from evaluating the policy. nil arguments operate as wildcards.
    #
    # @param name [String]
    # @param args [Array<[String, OsoCloud::Value, nil]>]
    # @param context_facts [Array<fact>]
    # @return [Array<fact>]
    # @see Oso for more information about facts
    def query(name, *args, context_facts: [])
      typed_args = args.map { |a| OsoCloud::Helpers.extract_value(a) }
      result = @api.post_query(OsoCloud::Core::Query.new(fact: OsoCloud::Helpers.param_to_fact(name, typed_args),
                                                         context_facts: OsoCloud::Helpers.params_to_facts(context_facts)))
      OsoCloud::Helpers.facts_to_params(result.results)
    end
  end
end
