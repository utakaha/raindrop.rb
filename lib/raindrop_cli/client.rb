# frozen_string_literal: true

require "faraday"
require "json"

require_relative "errors"

module RaindropCli
  class Client
    BASE_URL = "https://api.raindrop.io/rest/v1"

    def initialize(token:, connection: nil)
      @token = token
      @connection = connection || default_connection
    end

    def search_raindrops(query, perpage: 10, page: 0)
      response = @connection.get("raindrops/0") do |request|
        request.params.update(
          "search" => query,
          "perpage" => perpage,
          "page" => page
        )
      end
      handle_response(response)
    end

    def tags(collection_id: 0)
      response = @connection.get("tags/#{collection_id}")
      handle_response(response)
    end

    private

    def default_connection
      Faraday.new(url: BASE_URL) do |connection|
        connection.headers["Accept"] = "application/json"
        connection.headers["Authorization"] = "Bearer #{@token}"
      end
    end

    def handle_response(response)
      payload = parse_payload(response)
      return payload if response.success?

      raise ApiError, error_message(response, payload)
    end

    def parse_payload(response)
      body = response.body.to_s
      return {} if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError => e
      return {} unless response.success?

      raise ApiError, "Failed to parse API response: #{e.message}"
    end

    def error_message(response, payload)
      if response.status == 401
        return "Authentication failed. The stored token may be invalid. Run `raindrop auth token` again."
      end

      message = payload["errorMessage"] || payload["message"] || response.reason_phrase || "HTTP error"
      "API request failed: #{response.status} #{message}"
    end
  end
end
