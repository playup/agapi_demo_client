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

    def quick_pick_url_for_api_game_url(api_game_url)
      "#{app_base_url}/quickpick?game_url=#{CGI::escape(api_game_url)}"
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
        end ,
        :quick_pick_url => quick_pick_url_for_api_game_url(source_game['href'])
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

  get "/entry" do
    entry_representation = get_url(params[:entry_url])
    entry = OpenStruct.new({
      :placed_by => entry_representation['pup']['display_name'],
      :score => entry_representation['score_card']['total'],
      :score_card => OpenStruct.new({
        :players => entry_representation['score_card']['players'].map do |player|
          OpenStruct.new({
            :slot_number => player['slot_number'],
            :subbed? => player['subbed'],
            :name => "#{player['first_name']} #{player['last_name']}",
            :score => player['score'].map do |score|
              OpenStruct.new({
                :strength => score['strength'],
                :points => score['points']
              })
            end
          })
        end
      }),
      :rank => entry_representation['rank']['position'],
      :entry_count => entry_representation['rank']['entry_count'],
      :front_line => entry_representation['front_line'].map do |source_player|
        OpenStruct.new({
          :name => "#{source_player['first_name']} #{source_player['last_name']}",
          :team => OpenStruct.new(source_player['team'])
        })
      end
    })

    haml :entry, :locals => {:entry => entry}
  end

  post "/quickpick" do
    game_url = params[:game_url]
    game_representation = get_url(game_url)
    pick_representation = follow_link(:relation => 'new_entry', :on => game_representation)
    until form_exists_for?('entry', :on => pick_representation)
      picked_player = pick_representation['players'].first
      pick_representation = follow_link(:relation => 'pick', :on => picked_player)
    end
    new_entry_response = submit_form('entry', :on => pick_representation)
    raise "that didn't create properly" unless new_entry_response.created?

    entry_url = new_entry_response.headers['Location']
    redirect "/entry?entry_url=#{CGI::escape(entry_url)}"
  end

  def submit_form(relation, options)
    from_resource = options[:on]
    form = extract_form_for(relation, :on => from_resource)

    raise NotImplemetedError('Agape only supports POSTing forms') unless form['method'] == 'POST'
    raise NotImplemetedError('Agape only supports JSON forms') unless form['enctype'] == 'application/json'

    properties = form['properties'] || {}
    properties_with_values = properties.select {|name, details| details.has_key? 'value'}
    property_key = properties_with_values.map do |property_name,property|
      [property_name, property['value']]
    end
    payload = Hash[property_key]
    json_body = payload.to_json
    new_entry_resource = post_url(form['href'], json_body, 'Content-Type' => form['enctype'])
  end

  def form_exists_for?(relation, options)
    resource = options[:on]
    !!extract_form_for(relation, :on => resource)
  end


  def follow_link(options)
    relation = options[:relation]
    from_resource = options[:on]
    link = extract_relation_link from_resource, relation
    get_url(link['href'])
  end

  def get_url(url)
    url.to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).get.deserialise
  end

  def post_url(url, body, options = {})
    url.to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).post(body, options)
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
    raise ArgumentError unless resource
    raise ArgumentError unless resource.has_key? 'link'
    resource['link'].detect do |link|
      next unless link.has_key? 'rel'
      link['rel'].split.include? rel_name
    end
  end

  def extract_form_for(relationship, options)
    resource = options[:on]
    raise ArgumentError unless resource
    unless resource.has_key? 'link'
      puts "No link in #{resource.keys}"
      return nil
    end

    resource['link'].detect do |link|
      next unless link['rel'].split.include? relationship
      next unless link.has_key? 'enctype'
      true
    end
  end

end
