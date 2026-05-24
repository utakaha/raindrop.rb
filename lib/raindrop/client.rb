# frozen_string_literal: true

require "faraday"
require "json"

require_relative "errors"

module Raindrop
  class Client
    BASE_URL = "https://api.raindrop.io/rest/v1"

    def initialize(token:, connection: nil)
      @token = token
      @connection = connection || default_connection
    end

    def search_raindrops(query, collection_id: 0, perpage: 10, page: 0, sort: nil)
      response = @connection.get("raindrops/#{collection_id}") do |request|
        request.params.update(
          "search" => query,
          "perpage" => perpage,
          "page" => page
        )
        request.params["sort"] = sort unless sort.to_s.empty?
      end
      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "API request failed: #{e.message}"
    end

    def get_raindrop(id)
      response = @connection.get("raindrop/#{id}")
      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "API request failed: #{e.message}"
    end

    def create_raindrop(link, title: nil, excerpt: nil, note: nil, tags: [], collection_id: nil)
      response = @connection.post("raindrop") do |request|
        request.headers["Content-Type"] = "application/json"
        request.body = JSON.generate(create_raindrop_body(link, title, excerpt, note, tags, collection_id))
      end
      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "API request failed: #{e.message}"
    end

    def delete_raindrop(id)
      response = @connection.delete("raindrop/#{id}")
      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "API request failed: #{e.message}"
    end

    def tags(collection_id: 0)
      response = @connection.get("tags/#{collection_id}")
      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "API request failed: #{e.message}"
    end

    def root_collections
      response = @connection.get("collections")
      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "API request failed: #{e.message}"
    end

    def child_collections
      response = @connection.get("collections/childrens")
      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "API request failed: #{e.message}"
    end

    private

    def default_connection
      Faraday.new(url: BASE_URL) do |connection|
        connection.headers["Accept"] = "application/json"
        connection.headers["Authorization"] = "Bearer #{@token}"
      end
    end

    def create_raindrop_body(link, title, excerpt, note, tags, collection_id)
      body = {
        "link" => link,
        "pleaseParse" => {}
      }
      body["title"] = title unless title.to_s.empty?
      body["excerpt"] = excerpt unless excerpt.to_s.empty?
      body["note"] = note unless note.to_s.empty?
      body["tags"] = tags unless tags.empty?
      body["collection"] = { "$id" => collection_id } unless collection_id.nil?
      body
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
        return "Authentication failed. The stored token may be invalid. Run `raindrop auth login` again."
      end

      message = payload["errorMessage"] || payload["message"] || response.reason_phrase || "HTTP error"
      "API request failed: #{response.status} #{message}"
    end
  end
end
