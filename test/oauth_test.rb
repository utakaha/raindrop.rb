# frozen_string_literal: true

require "faraday"
require "json"

require_relative "test_helper"

class OAuthTest < Minitest::Test
  def test_authorization_url
    oauth = Raindrop::OAuth.new

    url = oauth.authorization_url(
      client_id: "client-id",
      redirect_uri: "http://localhost:4567/callback"
    )

    assert_equal(
      "https://api.raindrop.io/v1/oauth/authorize?response_type=code&client_id=client-id&redirect_uri=http%3A%2F%2Flocalhost%3A4567%2Fcallback",
      url
    )
  end

  def test_exchange_code_sends_json_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/oauth/access_token") do |env|
        assert_equal "application/json", env.request_headers["Accept"]
        assert_equal "application/json", env.request_headers["Content-Type"]
        assert_equal(
          {
            "grant_type" => "authorization_code",
            "code" => "auth-code",
            "client_id" => "client-id",
            "client_secret" => "client-secret",
            "redirect_uri" => "http://localhost:4567/callback"
          },
          JSON.parse(env.body)
        )

        [
          200,
          { "Content-Type" => "application/json" },
          {
            "access_token" => "access-token",
            "refresh_token" => "refresh-token",
            "expires_in" => 1_209_599,
            "token_type" => "Bearer"
          }.to_json
        ]
      end
    end

    payload = oauth_with(stubs).exchange_code(
      client_id: "client-id",
      client_secret: "client-secret",
      redirect_uri: "http://localhost:4567/callback",
      code: "auth-code"
    )

    assert_equal "access-token", payload.fetch("access_token")
    assert_equal "refresh-token", payload.fetch("refresh_token")
    stubs.verify_stubbed_calls
  end

  def test_exchange_code_reports_oauth_error
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/oauth/access_token") do
        [
          400,
          { "Content-Type" => "application/json" },
          { "error" => "bad_authorization_code" }.to_json
        ]
      end
    end

    error = assert_raises(Raindrop::ApiError) do
      oauth_with(stubs).exchange_code(
        client_id: "client-id",
        client_secret: "client-secret",
        redirect_uri: "http://localhost:4567/callback",
        code: "bad-code"
      )
    end

    assert_equal "OAuth request failed: 400 bad_authorization_code", error.message
    stubs.verify_stubbed_calls
  end

  def test_extracts_authorization_code_from_loopback_callback
    oauth = Raindrop::OAuth.new

    code = oauth.send(
      :authorization_code_from_request,
      "GET /callback?code=auth-code HTTP/1.1",
      expected_path: "/callback"
    )

    assert_equal "auth-code", code
  end

  private

  def oauth_with(stubs)
    connection = Faraday.new(url: Raindrop::OAuth::BASE_URL) do |builder|
      builder.headers["Accept"] = "application/json"
      builder.adapter :test, stubs
    end

    Raindrop::OAuth.new(connection: connection)
  end
end
