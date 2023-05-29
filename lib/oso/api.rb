require 'json'
require 'uri'
require 'faraday'
require 'faraday/retry'

require 'oso/helpers'
require 'oso/version'

module OsoCloud
  # @!visibility private
  module Core
    # @!visibility private
    class ApiResult
      attr_reader :message

      def initialize(message:)
        @message = message
      end
    end

    # @!visibility private
    class ApiError < StandardError
      def initialize(message:)
        super(message)
      end
    end

    # @!visibility private
    class Policy
      attr_reader :filename, :src

      def initialize(filename:, src:)
        @filename = filename
        @src = src
      end
    end

    # @!visibility private
    class GetPolicyResult
      attr_reader :policy

      def initialize(policy:)
        @policy = if policy.is_a? Policy
                    policy
                  else
                    Policy.new(**policy)
                  end
      end
    end

    # @!visibility private
    class Fact
      attr_reader :predicate, :args

      def initialize(predicate:, args:)
        @predicate = predicate
        @args = args.map { |v| (v.is_a? Value) ? v : Value.new(**v) }
      end
    end

    # @!visibility private
    class Value
      attr_reader :type, :id

      def initialize(type:, id:)
        @type = type
        @id = id
      end
    end

    # @!visibility private
    class Bulk
      attr_reader :delete, :tell

      def initialize(delete:, tell:)
        @delete = delete.map { |v| (v.is_a? Fact) ? v : Fact.new(**v) }
        @tell = tell.map { |v| (v.is_a? Fact) ? v : Fact.new(**v) }
      end
    end

    # @!visibility private
    class AuthorizeResult
      attr_reader :allowed

      def initialize(allowed:)
        @allowed = allowed
      end
    end

    # @!visibility private
    class AuthorizeQuery
      attr_reader :actor_type, :actor_id, :action, :resource_type, :resource_id, :context_facts

      def initialize(actor_type:, actor_id:, action:, resource_type:, resource_id:, context_facts:)
        @actor_type = actor_type
        @actor_id = actor_id
        @action = action
        @resource_type = resource_type
        @resource_id = resource_id
        @context_facts = context_facts.map { |v| (v.is_a? Fact) ? v : Fact.new(**v) }
      end
    end

    # @!visibility private
    class AuthorizeResourcesResult
      attr_reader :results

      def initialize(results:)
        @results = results.map { |v| (v.is_a? Value) ? v : Value.new(**v) }
      end
    end

    # @!visibility private
    class AuthorizeResourcesQuery
      attr_reader :actor_type, :actor_id, :action, :resources, :context_facts

      def initialize(actor_type:, actor_id:, action:, resources:, context_facts:)
        @actor_type = actor_type
        @actor_id = actor_id
        @action = action
        @resources = resources.map { |v| (v.is_a? Value) ? v : Value.new(**v) }
        @context_facts = context_facts.map { |v| (v.is_a? Fact) ? v : Fact.new(**v) }
      end
    end

    # @!visibility private
    class ListResult
      attr_reader :results

      def initialize(results:)
        @results = results
      end
    end

    # @!visibility private
    class ListQuery
      attr_reader :actor_type, :actor_id, :action, :resource_type, :context_facts

      def initialize(actor_type:, actor_id:, action:, resource_type:, context_facts:)
        @actor_type = actor_type
        @actor_id = actor_id
        @action = action
        @resource_type = resource_type
        @context_facts = context_facts.map { |v| (v.is_a? Fact) ? v : Fact.new(**v) }
      end
    end

    # @!visibility private
    class ActionsResult
      attr_reader :results

      def initialize(results:)
        @results = results
      end
    end

    # @!visibility private
    class ActionsQuery
      attr_reader :actor_type, :actor_id, :resource_type, :resource_id, :context_facts

      def initialize(actor_type:, actor_id:, resource_type:, resource_id:, context_facts:)
        @actor_type = actor_type
        @actor_id = actor_id
        @resource_type = resource_type
        @resource_id = resource_id
        @context_facts = context_facts.map { |v| (v.is_a? Fact) ? v : Fact.new(**v) }
      end
    end

    # @!visibility private
    class QueryResult
      attr_reader :results

      def initialize(results:)
        @results = results.map { |v| (v.is_a? Fact) ? v : Fact.new(**v) }
      end
    end

    # @!visibility private
    class Query
      attr_reader :fact, :context_facts

      def initialize(fact:, context_facts:)
        @fact = if fact.is_a? Fact
                  fact
                else
                  Fact.new(**fact)
                end
        @context_facts = context_facts.map { |v| (v.is_a? Fact) ? v : Fact.new(**v) }
      end
    end

    # @!visibility private
    class StatsResult
      attr_reader :num_roles, :num_relations, :num_facts

      def initialize(num_roles:, num_relations:, num_facts:)
        @num_roles = num_roles
        @num_relations = num_relations
        @num_facts = num_facts
      end
    end

    # @!visibility private
    class Api
      def initialize(url: 'https://api.osohq.com', api_key: nil, options: nil)
        @url = url
        @connection = Faraday.new(url: url) do |faraday|
          faraday.request :json

          # responses are processed in reverse order; this stack implies the
          # retries are attempted before an error is raised, and the json
          # parser is only applied if there are no errors
          faraday.response :json, parser_options: { symbolize_names: true }
          faraday.response :raise_error
          faraday.request :retry, {
            max: (options && options[:max_retries]) || 10,
            interval: 0.01,
            interval_randomness: 0.005,
            max_interval: 1,
            backoff_factor: 2,
            retry_statuses: [429, 500, 502, 503, 504],
            # ensure authorize and related check functions are retried because
            # they are POST requests, which are not retried automatically
            retry_if: lambda { |env, _exc|
              %w[
                /api/authorize
                /api/authorize_resources
                /api/list
                /api/actions
                /api/query
              ].include? env.url.path
            }
          }

          if options && options[:test_adapter]
            faraday.adapter :test do |stub|
              stub.post(options[:test_adapter][:path]) do |_env|
                options[:test_adapter][:func].call
              end
              stub.get(options[:test_adapter][:path]) do |_env|
                options[:test_adapter][:func].call
              end
              stub.delete(options[:test_adapter][:path]) do |_env|
                options[:test_adapter][:func].call
              end
            end
          else
            faraday.adapter :net_http
          end
        end
        @api_key = api_key
        @user_agent = "Oso Cloud (ruby #{RUBY_VERSION}p#{RUBY_PATCHLEVEL}; rv:#{VERSION})"
        @last_offset = nil
      end

      def get_policy
        url = '/policy'
        result = GET(url, nil)
        GetPolicyResult.new(**result)
      end

      def post_policy(data)
        url = '/policy'
        result = POST(url, nil, data, true)
        ApiResult.new(**result)
      end

      def post_facts(data)
        url = '/facts'
        result = POST(url, nil, data, true)
        Fact.new(**result)
      end

      def delete_facts(data)
        url = '/facts'
        result = DELETE(url, data)
        ApiResult.new(**result)
      end

      def post_bulk_load(data)
        url = '/bulk_load'
        result = POST(url, nil, data, true)
        ApiResult.new(**result)
      end

      def post_bulk_delete(data)
        url = '/bulk_delete'
        result = POST(url, nil, data, true)
        ApiResult.new(**result)
      end

      def post_bulk(data)
        url = '/bulk'
        result = POST(url, nil, data, true)
        ApiResult.new(**result)
      end

      def post_authorize(data)
        url = '/authorize'
        result = POST(url, nil, data, false)
        AuthorizeResult.new(**result)
      end

      def post_authorize_resources(data)
        url = '/authorize_resources'
        result = POST(url, nil, data, false)
        AuthorizeResourcesResult.new(**result)
      end

      def post_list(data)
        url = '/list'
        result = POST(url, nil, data, false)
        ListResult.new(**result)
      end

      def post_actions(data)
        url = '/actions'
        result = POST(url, nil, data, false)
        ActionsResult.new(**result)
      end

      def post_query(data)
        url = '/query'
        result = POST(url, nil, data, false)
        QueryResult.new(**result)
      end

      def get_stats
        url = '/stats'
        result = GET(url, {})
        StatsResult.new(**result)
      end

      def clear_data
        url = '/clear_data'
        result = POST(url, nil, nil, true)
        ApiResult.new(**result)
      end

      # hard-coded, not generated
      def get_facts(predicate, args)
        params = {}
        params['predicate'] = predicate
        args.each_with_index do |arg, i|
          next if arg.nil?

          arg_query = OsoCloud::Helpers.extract_arg_query(arg)
          if arg_query
            params["args.#{i}.type"] = arg_query.type
            params["args.#{i}.id"] = arg_query.id
          end
        end
        url = '/facts'
        result = GET(url, params)
        result.map { |v| Fact.new(**v) }
      end

      def headers
        default_headers = {
          'Authorization' => format('Bearer %s', @api_key),
          'User-Agent' => @user_agent,
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-OsoApiVersion': '0',
        }
        # set OsoOffset is last_offset is not nil
        default_headers[:OsoOffset] = @last_offset unless @last_offset.nil?
        default_headers
      end

      def GET(path, params)
        response = @connection.get("api#{path}")  do |req|
          req.params = params unless params.nil?
          req.headers = headers
        end
        response.body
      rescue Faraday::Error => e
        handle_faraday_error e
      end

      def POST(path, params, body, isMutation)
        response = @connection.post("api#{path}") do |req|
          req.params = params unless params.nil?
          req.body = OsoCloud::Helpers.to_hash(body) unless body.nil?
          req.headers = headers
        end

        if isMutation
          @last_offset = response.headers[:OsoOffset]
        end
        response.body
      rescue Faraday::Error => e
        handle_faraday_error e
      end

      def DELETE(path, body)
        response = @connection.delete("api#{path}") do |req|
          req.headers = headers
          req.body = OsoCloud::Helpers.to_hash(body) unless body.nil?
        end
        response.body
      rescue Faraday::Error => e
        handle_faraday_error e
      end

      def handle_faraday_error(error)
        resp = error.response
        err = if resp.respond_to? :body
            resp.body[:message]
        else
          error.message
        end
        raise ApiError.new(message: err)
      end
    end
  end
end
