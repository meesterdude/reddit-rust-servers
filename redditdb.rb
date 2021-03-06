#!/usr/bin/ruby

require 'JSON'
require 'pry'
require 'HTTParty'

# either numeric range or regex
SANITATIONS = {
    "slots" => 0..300,
    "airdrop-min-players" => 0..300,
    "donations" => /^(yes|no)$/,
    "pvp" => /^(yes|no)$/,
    "crafting-time-percent" => 0..500,
    "sleepers" => /^(yes|no)$/,
    "has-voice-server" => /^(yes|no)$/,
    "beginner-friendly" => /^(yes|no)$/,
    "reddit-contact-user" => /^\/u\/([a-z\d]+)$/i,
    "seeking-admins" => /^(yes|no)$/,
    "mini-games" =>  /^(yes|no)$/,
    "ip:port" => /^\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b:\d{3,5}$/,
    "location" => /^[a-z]{2}$/,
    "server-launched" => /^\d{4}-\d{2}-\d{2}$/,
    "entry-updated" => /^\d{4}-\d{2}-\d{2}$/,
    "site" => /^(http|https):\/\/.+$/,
    "forum" => /^(http|https):\/\/.+$/,
    "admin-power-usage" => /^(not used|for good|for gameplay|at will)$/
  }


class Reddit
  include HTTParty
  base_uri 'reddit.com'
  AGENT = "redditdb_bot/1.0 by ruru32"


  def initialize(sub)
    @subreddit = sub
  end

  def fetch_posts(search_for)
    query = "/search.json?q=#{search_for}&restrict_sr=on&sort=new&t=all&limit=100"
    response = self.class.get(@subreddit + query, :headers => {"User-Agent" => AGENT})
    posts = response['data']['children']
    after = response['data']['after']
    while after do
      sleep 2 # no more than 30 requests a minute per API spec
        query_val = query + "&after=#{after}"
      response = self.class.get(@subreddit + query_val, :headers => {"User-Agent" => AGENT})
      posts.concat response['data']['children']
      after = response['data']['after']
    end
    return posts
  end

  def sanitize(k,v)
    val = if SANITATIONS.keys.include?(k)
      sanitizer = SANITATIONS[k]
      result = case sanitizer.class.to_s
      when "Range" # because range regexes are ugly
        return false if v =~ /\D/
        sanitizer.cover?(v.to_i)
      when "Regexp"
        if v =~ sanitizer
          true
        elsif v.empty?
          true
        else
          @@has_failures = true
          puts "sanitize failed for #{k}. attribute was: #{v} "
          false
        end
      else
        false
      end
      result ? v : ""
    end
  end

  def parse_post(post)
    #TODO: figure out cleaner way to parse; partition fails regex.
    extracted_json = post['data']['selftext'].split('{').last.split('}').first
    begin
      JSON.parse("{" + extracted_json + "}")
    rescue JSON::ParserError
      @@has_failures = true
      puts "JSON parse failed"
    end
  end
end

# begin the magic

r = Reddit.new('/r/playrustservers')
posts = r.fetch_posts('(JAD)')
sanitized_a = Array.new

posts.each do |post|
  puts "------\n #{post['data']['url']}"
  result_h = r.parse_post(post)
  # do sanitations if it parsed
  unless result_h.nil?
    @@has_failures = false

    result_h.each do |k,v|
      k = k.downcase
      next unless SANITATIONS.keys.include?(k) # skip any we don't sanitize
      result_h[k] = r.sanitize(k, v.strip.downcase) || ""
    end

    # add computed attributes
    result_h['_post'] = post['data']['url']
    result_h['_post-author'] = "/u/" + post['data']['author']
    result_h['_ip-address'], result_h['_port']  = result_h['ip:port'].split(":")
    sanitized_a << result_h
  end
  puts "Please see /r/playrustservers/wiki/jad for formatting guidelines" if @@has_failures
end
puts "---------\nsucceeded:#{sanitized_a.size} failed:#{posts.count - sanitized_a.size} total: #{posts.count}"
json = {
  "generated" => Date.today.to_s,
  "specification" => 1,
  "servers" => sanitized_a
}
File.open("servers.json", 'w') {|f| f.write(JSON.pretty_generate(json))}
