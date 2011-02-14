require 'sinatra/base'
require 'wrest'
require 'active_support'

class GoalsReference < Sinatra::Base
  set :haml, :format => :html5, :escape_html => true
  
  helpers do
    def to_date_time(date_time_string)
      DateTime.parse(date_time_string).in_time_zone('Eastern Time (US & Canada)')
    end
  end
  
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
        :window_start => to_date_time(source_game['window_start']),
        :window_length => source_game['window_length'],
        :prize => OpenStruct.new(source_game['prize']),
        :matches => source_game['matches'].map do |match|
          OpenStruct.new({
            :scheduled_start => to_date_time(match['scheduled_start']),
            :home_team => match['home_team']['short_name'],
            :away_team => match['away_team']['short_name']
          })
        end
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
