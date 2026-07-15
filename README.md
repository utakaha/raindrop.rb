# raindrop.rb

`raindrop` is a Ruby command line client for [Raindrop.io](https://raindrop.io/).

It is built for everyday bookmark workflows from the terminal: authenticate with OAuth, search saved raindrops, inspect an item, add new links, update metadata, delete old ones, and list tags or collections.

## Installation

Install the gem:

```sh
gem install raindrop
```

Then check that the executable is available:

```sh
raindrop --help
```

## Quick Start

All URLs, IDs, names, and metadata in the examples are fictitious and do not refer to data from a real Raindrop.io account.

Create an OAuth application in Raindrop.io and register this Redirect URL:

```text
http://127.0.0.1:42813/callback
```

Log in with your OAuth client credentials:

```sh
raindrop auth login \
  --client-id CLIENT_ID \
  --client-secret CLIENT_SECRET
```

Search your saved raindrops:

```sh
raindrop search example
```

Inspect a raindrop:

```sh
raindrop get 1234567890
```

Add a new link:

```sh
raindrop add https://example.com/article
```

Update an existing raindrop:

```sh
raindrop update 1234567890 --title "Example Article" --tag example
```

## Authentication

`raindrop` supports OAuth authentication. Test token authentication is not supported.

The default OAuth Redirect URL is:

```text
http://127.0.0.1:42813/callback
```

When you run `auth login`, the CLI prints an authorization URL and starts a temporary local callback server on `127.0.0.1:42813`. Open the URL in your browser, authorize the app, and Raindrop.io redirects back to the local callback URL. The CLI then exchanges the authorization code for OAuth tokens and stores them in the config file.

```sh
raindrop auth login \
  --client-id CLIENT_ID \
  --client-secret CLIENT_SECRET
```

If your OAuth application uses a different Redirect URL, pass it explicitly:

```sh
raindrop auth login \
  --client-id CLIENT_ID \
  --client-secret CLIENT_SECRET \
  --redirect-uri http://127.0.0.1:42813/callback
```

Check the current authentication status:

```sh
raindrop auth status
```

Remove stored OAuth credentials:

```sh
raindrop auth logout
```

## Commands

### Search

Search saved raindrops:

```sh
raindrop search example
```

By default, `search` returns up to 50 items. You can specify a smaller limit:

```sh
raindrop search example --limit 20
```

Sort results:

```sh
raindrop search example --sort score
raindrop search example --sort -created
raindrop search example --sort title
```

Supported sort values are `-created`, `created`, `score`, `-sort`, `title`, `-title`, `domain`, and `-domain`. `score` requires a search query.

Fetch all matching pages with `--all`:

```sh
raindrop search example --all
```

`--all` waits one second between pages to avoid sending requests too aggressively. It cannot be combined with `--limit`.

Filter by tag:

```sh
raindrop search --tag example
raindrop search example --tag reference --tag tutorial
```

Filter by collection:

```sh
raindrop search --collection 12345678
raindrop search example --collection 12345678
```

When `--collection` is provided, the search query itself is optional.

Output JSON:

```sh
raindrop search example --json
```

### Get

Show a single saved raindrop:

```sh
raindrop get 1234567890
```

Output JSON:

```sh
raindrop get 1234567890 --json
```

### Add

Add a URL:

```sh
raindrop add https://example.com/article
```

Add a URL with metadata:

```sh
raindrop add https://example.com/article \
  --title "Example Article" \
  --description "Example article description" \
  --note "Read later" \
  --tag example \
  --tag reference \
  --collection 12345678
```

Output JSON:

```sh
raindrop add https://example.com/article --json
```

### Update

Update a saved raindrop by ID:

```sh
raindrop update 1234567890 \
  --title "Example Article" \
  --description "Example article description" \
  --note "Read later" \
  --tag example \
  --tag reference \
  --collection 12345678
```

At least one update option is required. Tags replace the raindrop's tag list with the tags passed on the command line.

Output JSON:

```sh
raindrop update 1234567890 --title "Example Article" --json
```

### Delete

Delete a saved raindrop by ID:

```sh
raindrop delete 1234567890
```

Output JSON:

```sh
raindrop delete 1234567890 --json
```

### Tags

List tags:

```sh
raindrop tags
```

Rename a tag in all collections:

```sh
raindrop tags rename old-tag new-tag
```

Restrict the rename to one collection:

```sh
raindrop tags rename old-tag new-tag --collection 12345678
```

When `--collection` is omitted, the tag is renamed across all collections. The old and new tag names must be different.

Output the API response as JSON:

```sh
raindrop tags rename old-tag new-tag --json
```

Merge two or more tags into one tag:

```sh
raindrop tags merge old-tag legacy-tag --into new-tag
```

Restrict the merge to one collection:

```sh
raindrop tags merge old-tag legacy-tag --into new-tag --collection 12345678
```

When `--collection` is omitted, the tags are merged across all collections. Duplicate source tags and the destination tag are removed from the source list, and at least two source tags must remain.

Output the API response as JSON:

```sh
raindrop tags merge old-tag legacy-tag --into new-tag --json
```

Show the available tag management commands:

```sh
raindrop tags --help
```

### Collections

List collections:

```sh
raindrop collections
```

## Configuration

The config file is stored under the XDG config directory. By default, this is:

```text
~/.config/raindrop-cli/config.yml
```

Show the actual config path:

```sh
raindrop config path
```

Show config status:

```sh
raindrop config
```

Example output:

```text
Auth: oauth
Access token: [REDACTED]
Refresh token: [REDACTED]
Token type: Bearer
Expires in: 3600
```

Access tokens and refresh tokens are never printed by `raindrop config`.

## Development

Install dependencies:

```sh
bundle install
```

Run the CLI from the working tree:

```sh
bin/raindrop --help
```

Run tests:

```sh
bundle exec rake test
```

Build the gem locally:

```sh
bundle exec gem build raindrop.gemspec
```

## License

MIT
