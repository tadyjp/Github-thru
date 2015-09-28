require 'sinatra/base'
require 'sinatra/reloader'
require 'omniauth'
require 'omniauth-github'
require 'redis'
require 'github_api'

require 'dotenv'
Dotenv.load(".env.#{ENV['RACK_ENV']}", '.env')

%w(
  REDIS_URL
  GITHUB_KEY
  GITHUB_SECRET
).each do |key|
  raise "ENV['#{key}'] must be set." if ENV[key].nil? || ENV[key].empty?
end

class Server < Sinatra::Base
  configure do
    set :sessions, true
    set :inline_templates, true
    set :redis, Redis.new(url: ENV['REDIS_URL'])
  end

  configure :development do
    register Sinatra::Reloader
  end

  use OmniAuth::Builder do
    provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET'], scope: 'user,repo,read:org'
  end

  get '/' do
    oauth_token = settings.redis.get('oauth_token')
    github_org = settings.redis.get('github_org')
    mapping_mapping = settings.redis.get 'mapping_mapping'

    erb <<EOS
      <p>
        <code>Github Token: #{oauth_token || '(not set)'}</code><br>
        <code>Github Org: #{github_org || '(not set)'}</code><br>
      </p>
      <p><a href="/auth/github">Login with Github</a></p><br>
      <p>
        <pre>#{mapping_mapping}</pre>
      <p><a href="/mapping">Mention mapping</a></p><br>
EOS
  end

  get '/mapping' do
    mapping_mapping = settings.redis.get 'mapping_mapping'

    erb <<EOS
      <code>github_account, slack_account</code>
      <form action="/mapping" method="post">
        <textarea name="mapping_mapping" cols="40" rows="40">#{mapping_mapping}</textarea>
        <input type="submit">
      </form>
      <br><br>
      <a href="/">Top</a>
EOS
  end

  post '/mapping' do
    settings.redis.set 'mapping_mapping', params[:mapping_mapping]
    redirect '/'
  end

  get '/auth/:provider/callback' do
    result = request.env['omniauth.auth']
    token = result['credentials']['token']

    settings.redis.set 'oauth_token', token

    redirect '/orgs'
    EOS
  end

  get '/orgs' do
    @github = Github.new oauth_token: settings.redis.get('oauth_token'), auto_pagination: true

    erb <<EOS
      <h1>Select Github Organization</h1>
      <form action="/orgs" method="post">
        <select name="github_org">
          <% @github.orgs.list.map do |org| %>
            <option value="<%= org.login %>"><%= org.login %></option>
          <% end %>
        </select>
        <input type="submit">
      </form>
EOS
  end

  post '/orgs' do
    settings.redis.set 'github_org', params[:github_org]
    redirect '/'
  end
end
