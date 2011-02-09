require 'sinatra/base'
require 'wrest'
require 'active_support'

class GoalsReference < Sinatra::Base
  set :haml, :format => :html5
  
  get '/' do
    entry = 'http://goals-api.localhost/v1'.to_uri.get.deserialise
    games_link = entry['link'].detect {|link| link['rel'] == 'games'}
    games_representation = games_link['href'].to_uri(:verify_mode => OpenSSL::SSL::VERIFY_NONE, :username => 'ray', :password => 'password').get.deserialise
    games = games_representation['games'].map do |source_game|
      OpenStruct.new({
        :window_start => DateTime.parse(source_game['window_start']).in_time_zone('Eastern Time (US & Canada)'),
        :window_length => source_game['window_length']
      })
    end
    haml :index, :locals => {:games => games}
  end

end
