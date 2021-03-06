require "connection_pool"
require "redis"
require "sinatra"
require "twitter"

configure do
  set :server, "puma"

  if ENV["REDIS_URL_KEY"]
    pool = ConnectionPool::Wrapper.new(size: 5, timeout: 5) do
      Redis.new(url: ENV.fetch(ENV["REDIS_URL_KEY"]))
    end
    set :redis, pool
  else
    set :redis, Redis.new
  end
end

before do
  # One Twitter client per request thread
  @twitter = Twitter::REST::Client.new do |config|
    config.consumer_key    = ENV.fetch("TWITTER_CONSUMER_KEY")
    config.consumer_secret = ENV.fetch("TWITTER_CONSUMER_SECRET")
    config.bearer_token    = ENV["TWITTER_BEARER_TOKEN"] # optional
  end
end

get "/" do
  "<h3>Twitter username:</h3><form action=/screen_name><input type='text' name='screen_name'></input>"
end

get "/screen_name" do
  screen_name = CGI.escape(params[:screen_name])
  redirect "/#{screen_name}"
end

get "/:screen_name" do
  screen_name = params[:screen_name]

  enable_mentions_check_for(screen_name)

  seen_id = redis.get("#{screen_name}:last_seen_id")
  sent_id = redis.get("#{screen_name}:last_sent_id")

  halt 404, "Not found\n" if seen_id.nil?

  if sent_id && sent_id >= seen_id
    redis.set("#{screen_name}:last_sent_id", seen_id, ex: 30)
  end

  content_type "text/plain"
  body redis.get("#{screen_name}:last_seen_tweet") << "\n"
end

helpers do

  def redis
    settings.redis
  end

  def twitter
    @twitter
  end

  def enable_mentions_check_for(screen_name)
    return if redis.get("screen_name:#{screen_name}")

    if screen_name_exists?(screen_name)
      redis.set("screen_name:#{screen_name}", 1, ex: 30)
      sleep 4 # so the worker can notice and start monitoring
      halt 201, "Now checking for new mentions...\n"
    else
      halt 404, "Screen name #{screen_name} does not exist\n"
    end
  end

  def screen_name_exists?(screen_name)
    twitter.user(screen_name)
  rescue Twitter::Error::NotFound
    false
  end

end