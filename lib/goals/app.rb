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

    def game_entries_url(entries_link)
      "#{app_base_url}/entries?game_entries_url=#{CGI::escape(entries_link['href'])}"
    end

    def match_url(match)      
      "#{app_base_url}/match?match_url=#{CGI::escape(match.href)}"
    end

    def team_url(team)
      "#{app_base_url}/team?team_url=#{CGI::escape(team.href)}"
    end

    def player_url(player)
      "#{app_base_url}/player?player_url=#{CGI::escape(player.href)}"
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
    base = api_base_url.to_uri.get.deserialise

    me_representation = follow_link :relation => 'me', :on => base

    decided_entries_representation = follow_link :relation => 'decided_entries', :on => me_representation

    me = OpenStruct.new({
      :display_name => me_representation['display_name'],
      :member_since => to_date_time(me_representation['member_since']),
      :decided_entries => decided_entries_representation['entries'].map do |entry_link|
        entry_representation = entry_link['href'].to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).get.deserialise
        OpenStruct.new({
          :front_line => entry_representation['front_line'].map do |player|
            OpenStruct.new({:first_name => player['first_name'], :last_name => player['last_name']})
          end,
          :prize => OpenStruct.new({
            :cash => entry_representation['prize']['cash']['display'],
            :reward_points => entry_representation['prize']['reward_points'],
            :skill_ranking_points => entry_representation['prize']['skill_ranking_points']
          })
        })
      end
    })

    games_representation = follow_link :relation => 'games', :on => base

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
            :away_team => OpenStruct.new(match['away_team']),
            :href => match['href']      
          })
        end ,
        :quick_pick_url => quick_pick_url_for_api_game_url(source_game['href']),
        :entries_url => game_entries_url(extract_relation_link(source_game, 'entries'))
      })
    end

    interesting_games, other_games = all_games.partition do |game|
      game.window_length == 'daily'
    end
    haml :index, :locals => {:games => interesting_games, :config => config, :me => me}
  end

  get "/match" do
    match_url = params[:match_url]
    match_representation = match_url.to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).get.deserialise
    match_hash = match_representation['match']
    
    match = OpenStruct.new({
            :home_team => match_hash['home_team']['name'],
            :home_short => match_hash['home_team']['short_name'],
            :away_team => match_hash['away_team']['name'],
            :away_short => match_hash['away_team']['short_name'],
            :scheduled_start => match_hash['scheduled_start']
    })

    haml :'matches/show', :locals => {:match => match}
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

  get "/player" do
    player_url = params[:player_url]
    player_representation = player_url.to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).get.deserialise
    player_hash = player_representation['player']
    
    player = OpenStruct.new({
            :first_name => player_hash['first_name'],
            :last_name => player_hash['last_name'],
            :shirt_number => player_hash['shirt_number'],
            :position => player_hash['position'],
            :tier => player_hash['tier'],
            :goals => player_hash['goals']['total'],
            :total_bonus => player_hash['goals']['total_bonus']
    })

    haml :'players/show', :locals => {:player => player}
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


  get "/entries" do
    entries_representation = get_url(params['game_entries_url'])

    entries = entries_representation['entries'].map do |entry_representation|
      OpenStruct.new({
              :rank => entry_representation['rank']['position'],
              :score => entry_representation['score'],
              :pup_display_name => entry_representation['pup_display_name']
              })
    end

    haml :entries, :locals => {:entries => entries}

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
