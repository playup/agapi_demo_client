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
    games_link = entry['link'].detect {|link| link['rel'] == 'games'}
    games_representation = games_link['href'].to_uri(:verify_mode => OpenSSL::SSL::VERIFY_NONE, :username => 'ray', :password => 'password').get.deserialise
    games = games_representation['games'].map do |source_game|
      OpenStruct.new({
        :window_start => DateTime.parse(source_game['window_start']).in_time_zone('Eastern Time (US & Canada)'),
        :window_length => source_game['window_length']
      })
    end
    statistics = OpenStruct.new :number_of_requests => 2
    haml :index, :locals => {:games => games, :config => config, :statistics => statistics}
  end
  
  def config
    @confg ||= OpenStruct.new({
      :base_url => 'http://goals-api.localhost/v1'
    })
  end

end
