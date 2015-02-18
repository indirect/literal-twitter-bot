require "redis"
require "twitter"

class Worker
  attr_reader :twitter, :redis

  def initialize
    @twitter = Twitter::REST::Client.new do |config|
      config.consumer_key    = ENV.fetch("TWITTER_CONSUMER_KEY")
      config.consumer_secret = ENV.fetch("TWITTER_CONSUMER_SECRET")
      config.bearer_token    = ENV["TWITTER_BEARER_TOKEN"] # optional
    end

    if ENV["REDIS_URL_KEY"]
      @redis = Redis.new(url: ENV.fetch(ENV["REDIS_URL_KEY"]))
    else
      @redis = Redis.new
    end
  end

  def run!
    loop do
      @redis.keys("screen_name:*").each do |key|
        screen_name = key.split(":", 2).last
        puts "Updating last mention for @#{screen_name}"
        update_last_seen_id(screen_name)
      end

      sleep 4
    end
  end

private

  def update_last_seen_id(screen_name)
    last_seen_id = redis.get("#{screen_name}:last_seen_id")
    last = mentions_for(screen_name, last_seen_id).first

    if last_seen_id.nil? || (last && last.id > last_seen_id.to_i)
      redis.set("#{screen_name}:last_seen_id", last.id, ex: 60)
      redis.set("#{screen_name}:last_seen_tweet", "#{last.user.screen_name}: #{last.full_text}", ex: 60)
    end
  end

  def mentions_for(screen_name, last_id)
    options = {result_type: "recent"}
    options[:since_id] = last_id if last_id

    twitter.search("to:#{screen_name}", options)
  rescue Twitter::Error::TooManyRequests => error
    puts "rate limited, waiting #{error.rate_limit.reset_in} seconds"
    sleep error.rate_limit.reset_in + 1
    retry
  end

end
