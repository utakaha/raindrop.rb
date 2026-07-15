# frozen_string_literal: true

require 'faraday'
require 'json'

require_relative 'test_helper'

class ClientTest < Minitest::Test
  def test_search_raindrops_sends_authorized_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get('/rest/v1/raindrops/123') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']
        assert_equal 'example reference', env.params.fetch('search')
        assert_equal '50', env.params.fetch('perpage')
        assert_equal '2', env.params.fetch('page')
        assert_equal '-created', env.params.fetch('sort')

        [
          200,
          { 'Content-Type' => 'application/json' },
          {
            'items' => [
              {
                '_id' => 123,
                'title' => 'Example Article',
                'link' => 'https://example.com/article'
              }
            ]
          }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').search_raindrops(
      'example reference',
      collection_id: 123,
      perpage: 50,
      page: 2,
      sort: '-created'
    )

    assert_equal 123, payload.fetch('items').first.fetch('_id')
    stubs.verify_stubbed_calls
  end

  def test_search_raindrops_reports_unauthorized
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get('/rest/v1/raindrops/0') do
        [
          401,
          { 'Content-Type' => 'application/json' },
          { 'errorMessage' => 'Unauthorized' }.to_json
        ]
      end
    end

    error = assert_raises(Raindrop::ApiError) do
      client_with(stubs, token: 'bad-token').search_raindrops('example')
    end

    assert_includes error.message, 'Authentication failed.'
    stubs.verify_stubbed_calls
  end

  def test_search_raindrops_reports_api_error_message
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get('/rest/v1/raindrops/0') do
        [
          500,
          { 'Content-Type' => 'application/json' },
          { 'errorMessage' => 'Server failed' }.to_json
        ]
      end
    end

    error = assert_raises(Raindrop::ApiError) do
      client_with(stubs, token: 'secret-token').search_raindrops('example')
    end

    assert_equal 'API request failed: 500 Server failed', error.message
    stubs.verify_stubbed_calls
  end

  def test_search_raindrops_reports_non_json_api_error
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get('/rest/v1/raindrops/0') do
        [
          404,
          { 'Content-Type' => 'text/html' },
          '<!DOCTYPE html>'
        ]
      end
    end

    error = assert_raises(Raindrop::ApiError) do
      client_with(stubs, token: 'secret-token').search_raindrops('example')
    end

    assert_equal 'API request failed: 404 HTTP error', error.message
    stubs.verify_stubbed_calls
  end

  def test_get_raindrop_sends_authorized_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get('/rest/v1/raindrop/1234567890') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']

        [
          200,
          { 'Content-Type' => 'application/json' },
          {
            'item' => {
              '_id' => 1_234_567_890,
              'title' => 'Example Article',
              'link' => 'https://example.com/article'
            }
          }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').get_raindrop(1_234_567_890)

    assert_equal 1_234_567_890, payload.fetch('item').fetch('_id')
    stubs.verify_stubbed_calls
  end

  def test_create_raindrop_sends_authorized_json_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/rest/v1/raindrop') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']
        assert_equal 'application/json', env.request_headers['Content-Type']
        assert_equal(
          {
            'link' => 'https://example.com/article',
            'pleaseParse' => {}
          },
          JSON.parse(env.body)
        )

        [
          200,
          { 'Content-Type' => 'application/json' },
          {
            'item' => {
              '_id' => 123,
              'title' => 'Example Article',
              'link' => 'https://example.com/article'
            }
          }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').create_raindrop('https://example.com/article')

    assert_equal 123, payload.fetch('item').fetch('_id')
    stubs.verify_stubbed_calls
  end

  def test_create_raindrop_sends_optional_fields
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/rest/v1/raindrop') do |env|
        assert_equal(
          {
            'link' => 'https://example.com/article',
            'pleaseParse' => {},
            'title' => 'Example Article',
            'excerpt' => 'Example article description',
            'note' => 'Read later',
            'tags' => ['example', 'reference'],
            'collection' => { '$id' => 12_345_678 }
          },
          JSON.parse(env.body)
        )

        [
          200,
          { 'Content-Type' => 'application/json' },
          {
            'item' => {
              '_id' => 123,
              'title' => 'Example Article',
              'link' => 'https://example.com/article'
            }
          }.to_json
        ]
      end
    end

    client_with(stubs, token: 'secret-token').create_raindrop(
      'https://example.com/article',
      title: 'Example Article',
      excerpt: 'Example article description',
      note: 'Read later',
      tags: ['example', 'reference'],
      collection_id: 12_345_678
    )

    stubs.verify_stubbed_calls
  end

  def test_update_raindrop_sends_authorized_json_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.put('/rest/v1/raindrop/1234567890') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']
        assert_equal 'application/json', env.request_headers['Content-Type']
        assert_equal(
          {
            'title' => 'Example Article',
            'excerpt' => 'Example article description',
            'note' => 'Read later',
            'tags' => ['example', 'reference'],
            'collection' => { '$id' => 12_345_678 }
          },
          JSON.parse(env.body)
        )

        [
          200,
          { 'Content-Type' => 'application/json' },
          {
            'item' => {
              '_id' => 1_234_567_890,
              'title' => 'Example Article',
              'link' => 'https://example.com/article'
            }
          }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').update_raindrop(
      1_234_567_890,
      title: 'Example Article',
      excerpt: 'Example article description',
      note: 'Read later',
      tags: ['example', 'reference'],
      collection_id: 12_345_678
    )

    assert_equal 1_234_567_890, payload.fetch('item').fetch('_id')
    stubs.verify_stubbed_calls
  end

  def test_update_raindrop_omits_unspecified_fields
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.put('/rest/v1/raindrop/1234567890') do |env|
        assert_equal(
          {
            'title' => 'Example Article'
          },
          JSON.parse(env.body)
        )

        [
          200,
          { 'Content-Type' => 'application/json' },
          {
            'item' => {
              '_id' => 1_234_567_890,
              'title' => 'Example Article'
            }
          }.to_json
        ]
      end
    end

    client_with(stubs, token: 'secret-token').update_raindrop(1_234_567_890, title: 'Example Article')

    stubs.verify_stubbed_calls
  end

  def test_delete_raindrop_sends_authorized_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.delete('/rest/v1/raindrop/1234567890') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']

        [
          200,
          { 'Content-Type' => 'application/json' },
          { 'result' => true }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').delete_raindrop(1_234_567_890)

    assert_equal true, payload.fetch('result')
    stubs.verify_stubbed_calls
  end

  def test_tags_sends_authorized_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get('/rest/v1/tags/0') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']

        [
          200,
          { 'Content-Type' => 'application/json' },
          {
            'items' => [
              {
                '_id' => 'example',
                'count' => 12
              }
            ]
          }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').tags

    assert_equal 'example', payload.fetch('items').first.fetch('_id')
    stubs.verify_stubbed_calls
  end

  def test_rename_tag_sends_authorized_json_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.put('/rest/v1/tags/0') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']
        assert_equal 'application/json', env.request_headers['Content-Type']
        assert_equal(
          {
            'tags' => ['old-tag'],
            'replace' => 'example'
          },
          JSON.parse(env.body)
        )

        [
          200,
          { 'Content-Type' => 'application/json' },
          { 'result' => true }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').rename_tag('old-tag', replacement: 'example')

    assert_equal true, payload.fetch('result')
    stubs.verify_stubbed_calls
  end

  def test_merge_tags_sends_authorized_json_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.put('/rest/v1/tags/12345678') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']
        assert_equal 'application/json', env.request_headers['Content-Type']
        assert_equal(
          {
            'tags' => ['old-tag', 'legacy-tag'],
            'replace' => 'example'
          },
          JSON.parse(env.body)
        )

        [
          200,
          { 'Content-Type' => 'application/json' },
          { 'result' => true }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').merge_tags(
      ['old-tag', 'legacy-tag'],
      replacement: 'example',
      collection_id: 12_345_678
    )

    assert_equal true, payload.fetch('result')
    stubs.verify_stubbed_calls
  end

  def test_remove_tags_sends_authorized_json_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.delete('/rest/v1/tags/12345678') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']
        assert_equal 'application/json', env.request_headers['Content-Type']
        assert_equal(
          {
            'tags' => ['unused-tag', 'temporary-tag']
          },
          JSON.parse(env.body)
        )

        [
          200,
          { 'Content-Type' => 'application/json' },
          { 'result' => true }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').remove_tags(
      ['unused-tag', 'temporary-tag'],
      collection_id: 12_345_678
    )

    assert_equal true, payload.fetch('result')
    stubs.verify_stubbed_calls
  end

  def test_root_collections_sends_authorized_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get('/rest/v1/collections') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']

        [
          200,
          { 'Content-Type' => 'application/json' },
          {
            'items' => [
              {
                '_id' => 123,
                'title' => 'Sample Collection',
                'count' => 16
              }
            ]
          }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').root_collections

    assert_equal 123, payload.fetch('items').first.fetch('_id')
    stubs.verify_stubbed_calls
  end

  def test_child_collections_sends_authorized_request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get('/rest/v1/collections/childrens') do |env|
        assert_equal 'Bearer secret-token', env.request_headers['Authorization']
        assert_equal 'application/json', env.request_headers['Accept']

        [
          200,
          { 'Content-Type' => 'application/json' },
          {
            'items' => [
              {
                '_id' => 456,
                'title' => 'Example Article',
                'count' => 8
              }
            ]
          }.to_json
        ]
      end
    end

    payload = client_with(stubs, token: 'secret-token').child_collections

    assert_equal 456, payload.fetch('items').first.fetch('_id')
    stubs.verify_stubbed_calls
  end

  def test_search_raindrops_reports_connection_failure
    connection = Object.new
    def connection.get(_path)
      raise Faraday::ConnectionFailed, 'network is unreachable'
    end
    client = Raindrop::Client.new(token: 'secret-token', connection: connection)

    error = assert_raises(Raindrop::ApiError) do
      client.search_raindrops('example')
    end
    assert_equal 'API request failed: network is unreachable', error.message
  end

  private

  def client_with(stubs, token:)
    connection = Faraday.new(url: Raindrop::Client::BASE_URL) do |builder|
      builder.headers['Accept'] = 'application/json'
      builder.headers['Authorization'] = "Bearer #{token}"
      builder.adapter :test, stubs
    end

    Raindrop::Client.new(token: token, connection: connection)
  end
end
