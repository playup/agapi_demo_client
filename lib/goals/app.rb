require 'sinatra/base'
require 'wrest'
require 'active_support'

class GoalsReference < Sinatra::Base
  set :haml, :format => :html5, :escape_html => true
  
  error do
    @error = env['sinatra.error']
    haml :error
  end
  
  get '/' do
    base_url = params['base_url'] || config.base_url
    entry = base_url.to_uri.get.deserialise
    games_link = entry['link'].detect {|link| link['rel'].split.include? 'games'}
    
    games_representation = games_link['href'].to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).get.deserialise
    all_games = games_representation['games'].map do |source_game|
      OpenStruct.new({
        :window_start => DateTime.parse(source_game['window_start']).in_time_zone('Eastern Time (US & Canada)'),
        :window_length => source_game['window_length'],
        :prize => OpenStruct.new(source_game['prize'])
      })
    end
    interesting_games, other_games = all_games.partition do |game|
      game.window_length == 'daily'
    end
    statistics = OpenStruct.new :number_of_requests => 2
    haml :index, :locals => {:games => interesting_games, :config => config, :statistics => statistics}
  end
  
  def config
    @confg ||= OpenStruct.new({
      # :base_url => 'http://goals-api.heroku.com/v1',
      :base_url => 'http://localhost:3000/api/goals/v1',
      :username => 'ray',
      :password => 'password',
      # :ssl_verify_mode => OpenSSL::SSL::VERIFY_PEER # verify
      :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE # don't verify
    })
  end
  

end
