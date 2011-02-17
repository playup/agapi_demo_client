require 'sinatra/base'
require 'wrest'
require 'active_support'

class GoalsReference < Sinatra::Base
  set :haml, :format => :html5, :escape_html => true
    
  helpers do
    def to_date_time(date_time_string)
      DateTime.parse(date_time_string).in_time_zone('Eastern Time (US & Canada)')
    end

    def api_base_url
      params['base_url'] || config.base_url
    end
    
    def app_base_url
      # XXX: Does not support 'script name', i.e. a path - add this.
      @app_base_url ||= "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
    end
    
    def team_url(team)
      "#{app_base_url}/team?team_url=#{CGI::escape(team.href)}"
    end
  end
  
  error do
    @error = env['sinatra.error']
    haml :error
  end
  
  get '/' do
    entry = api_base_url.to_uri.get.deserialise
    games_link = extract_relation_link(entry, 'games')
    
    games_representation = games_link['href'].to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).get.deserialise
      
    all_games = games_representation['games'].map do |source_game|
      OpenStruct.new({
        :window_start => to_date_time(source_game['window_start']),
        :window_length => source_game['window_length'],
        :prize => OpenStruct.new({
            :cash => source_game['prize']['cash']['display'],
            :reward_points => source_game['prize']['reward_points'],
            :skill_ranking_points => source_game['prize']['skill_ranking_points']
          }),
        :matches => source_game['matches'].map do |match|
          OpenStruct.new({
            :scheduled_start => to_date_time(match['scheduled_start']),
            :home_team => OpenStruct.new(match['home_team']),
            :away_team => OpenStruct.new(match['away_team'])
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
  
  get "/team" do
    team_url = params[:team_url]
    team_representation = team_url.to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).get.deserialise
    team = OpenStruct.new(team_representation)
    players_link = extract_relation_link(team_representation, 'players')
    players_representation = players_link['href'].to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).get.deserialise
    
    team_players = players_representation['players'].map do |source_player|
      OpenStruct.new(source_player)
    end
    
    haml :'teams/show', :locals => {:team => team, :players => team_players}
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
  
  def extract_relation_link resource, rel_name
    resource['link'].detect {|link| link['rel'].split.include? rel_name}
  end
  
end
