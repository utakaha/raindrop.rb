# frozen_string_literal: true

require "faraday"
require "json"

require_relative "test_helper"

class ClientTest < Minitest::Test
  def test_search_raindrops_sends_authorized_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/rest/v1/raindrops/0") do |env|
        assert_equal "Bearer secret-token", env.request_headers["Authorization"]
        assert_equal "application/json", env.request_headers["Accept"]
        assert_equal "ruby docs", env.params.fetch("search")
        assert_equal "50", env.params.fetch("perpage")
        assert_equal "2", env.params.fetch("page")

        [
          200,
          { "Content-Type" => "application/json" },
          {
            "items" => [
              {
                "_id" => 123,
                "title" => "Ruby",
                "link" => "https://www.ruby-lang.org/"
              }
            ]
          }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: "secret-token").search_raindrops("ruby docs", perpage: 50, page: 2)

    assert_equal 123, payload.fetch("items").first.fetch("_id")
    stubs.verify_stubbed_calls
  end

  def test_search_raindrops_reports_unauthorized
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/rest/v1/raindrops/0") do
        [
          401,
          { "Content-Type" => "application/json" },
          { "errorMessage" => "Unauthorized" }.to_json
        ]
      end
    end

    error = assert_raises(RaindropCli::ApiError) do
      client_with(stubs, token: "bad-token").search_raindrops("ruby")
    end

    assert_includes error.message, "Authentication failed."
    stubs.verify_stubbed_calls
  end

  def test_search_raindrops_reports_api_error_message
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/rest/v1/raindrops/0") do
        [
          500,
          { "Content-Type" => "application/json" },
          { "errorMessage" => "Server failed" }.to_json
        ]
      end
    end

    error = assert_raises(RaindropCli::ApiError) do
      client_with(stubs, token: "secret-token").search_raindrops("ruby")
    end

    assert_equal "API request failed: 500 Server failed", error.message
    stubs.verify_stubbed_calls
  end

  def test_search_raindrops_reports_non_json_api_error
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/rest/v1/raindrops/0") do
        [
          404,
          { "Content-Type" => "text/html" },
          "<!DOCTYPE html>"
        ]
      end
    end

    error = assert_raises(RaindropCli::ApiError) do
      client_with(stubs, token: "secret-token").search_raindrops("ruby")
    end

    assert_equal "API request failed: 404 HTTP error", error.message
    stubs.verify_stubbed_calls
  end

  def test_tags_sends_authorized_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/rest/v1/tags/0") do |env|
        assert_equal "Bearer secret-token", env.request_headers["Authorization"]
        assert_equal "application/json", env.request_headers["Accept"]

        [
          200,
          { "Content-Type" => "application/json" },
          {
            "items" => [
              {
                "_id" => "ruby",
                "count" => 12
              }
            ]
          }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: "secret-token").tags

    assert_equal "ruby", payload.fetch("items").first.fetch("_id")
    stubs.verify_stubbed_calls
  end

  private

  def client_with(stubs, token:)
    connection = Faraday.new(url: RaindropCli::Client::BASE_URL) do |builder|
      builder.headers["Accept"] = "application/json"
      builder.headers["Authorization"] = "Bearer #{token}"
      builder.adapter :test, stubs
    end

    RaindropCli::Client.new(token: token, connection: connection)
  end
end
