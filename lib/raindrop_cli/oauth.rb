# frozen_string_literal: true

require "faraday"
require "json"
require "socket"
require "uri"

require_relative "errors"

module RaindropCli
  class OAuth
    BASE_URL = "https://api.raindrop.io/v1"
    AUTHORIZATION_URL = "#{BASE_URL}/oauth/authorize"
    DEFAULT_REDIRECT_URI = "http://127.0.0.1:42813/callback"

    def initialize(connection: nil)
      @connection = connection || default_connection
    end

    def authorization_url(client_id:, redirect_uri:)
      query = URI.encode_www_form(
        "response_type" => "code",
        "client_id" => client_id,
        "redirect_uri" => redirect_uri
      )
      "#{AUTHORIZATION_URL}?#{query}"
    end

    def exchange_code(client_id:, client_secret:, redirect_uri:, code:)
      response = @connection.post("oauth/access_token") do |request|
        request.headers["Content-Type"] = "application/json"
        request.body = JSON.generate(
          "grant_type" => "authorization_code",
          "code" => code,
          "client_id" => client_id,
          "client_secret" => client_secret,
          "redirect_uri" => redirect_uri
        )
      end
      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      raise ApiError, "OAuth request failed: #{e.message}"
    end

    def receive_authorization_code(redirect_uri:)
      redirect = URI.parse(redirect_uri)
      server = TCPServer.new(redirect.host, redirect.port)
      socket = server.accept
      request_line = socket.gets.to_s
      code = authorization_code_from_request(request_line, expected_path: redirect.path)
      write_callback_response(socket, "Authentication complete. You can close this window.")
      code
    ensure
      socket&.close
      server&.close
    end

    private

    def default_connection
      Faraday.new(url: BASE_URL) do |connection|
        connection.headers["Accept"] = "application/json"
      end
    end

    def handle_response(response)
      payload = parse_payload(response)
      return payload if response.success?

      message = payload["error"] || payload["errorMessage"] || payload["message"] || response.reason_phrase || "HTTP error"
      raise ApiError, "OAuth request failed: #{response.status} #{message}"
    end

    def parse_payload(response)
      body = response.body.to_s
      return {} if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError => e
      return {} unless response.success?

      raise ApiError, "Failed to parse OAuth response: #{e.message}"
    end

    def authorization_code_from_request(request_line, expected_path:)
      target = request_line.split[1].to_s
      raise AuthenticationError, "Authorization code is empty." if target.empty?

      uri = URI.parse(target)
      raise AuthenticationError, "Unexpected OAuth callback path: #{uri.path}" unless uri.path == expected_path

      query = URI.decode_www_form(uri.query.to_s).to_h
      raise AuthenticationError, "OAuth authorization failed: #{query.fetch("error")}" if query.key?("error")

      code = query.fetch("code", "").to_s.strip
      raise AuthenticationError, "Authorization code is empty." if code.empty?

      code
    rescue URI::InvalidURIError
      raise AuthenticationError, "Authorization code is empty."
    end

    def write_callback_response(socket, body)
      socket.write "HTTP/1.1 200 OK\r\n"
      socket.write "Content-Type: text/plain; charset=utf-8\r\n"
      socket.write "Content-Length: #{body.bytesize}\r\n"
      socket.write "Connection: close\r\n"
      socket.write "\r\n"
      socket.write body
    end
  end
end
