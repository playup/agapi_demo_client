require 'sinatra/base'
require 'wrest'
require 'active_support'

Wrest::Caching.default_to_memcached!

class GoalsReference < Sinatra::Base
  set :haml, :format => :html5, :escape_html => true

  helpers do
    def to_date_time(date_time_string)
      DateTime.parse(date_time_string).in_time_zone('Eastern Time (US & Canada)')  if date_time_string
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

    def game_entry_url(entry)
      "#{app_base_url}/entry?entry_url=#{CGI::escape(entry.href)}"
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

    def my_entries_awaiting_decision_url(pup)
      "#{app_base_url}/pups_entries_awaiting_decision?entries_awaiting_decision_url=#{CGI::escape(pup.entries_awaiting_decision_url)}"
    end

    def my_decided_entries_url(pup)
      "#{app_base_url}/pups_decided_entries?decided_entries_url=#{CGI::escape(pup.decided_entries_url)}"
    end

    def transactions_url(pup)
     "#{app_base_url}/transactions?transactions_url=#{CGI::escape(pup.transactions_url)}"
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
    base = get_url(api_base_url)

    me_representation = follow_link :relation => 'me', :on => base

    decided_entries_representation = follow_link :relation => 'decided_entries', :on => me_representation

    me = OpenStruct.new({
      :display_name => me_representation['display_name'],
      :member_since => to_date_time(me_representation['member_since']),
      :entries_awaiting_decision_url => extract_relation_link(me_representation, 'entries_awaiting_decision')['href'],
      :decided_entries_url => extract_relation_link(me_representation, 'decided_entries')['href'],
      :transactions_url => extract_relation_link(me_representation, 'transactions')['href'],
      :decided_entries => decided_entries_representation['entries'].map do |entry_link|
        entry_representation = get_url(entry_link['href'])
        OpenStruct.new({
          :front_line => entry_representation['front_line'].map do |player|
            OpenStruct.new(player)
          end,
          :prize => OpenStruct.new({
            :cash => entry_representation['prize']['cash']['display'],
            :reward_points => entry_representation['prize']['reward_points'],
            :skill_ranking_points => entry_representation['prize']['skill_ranking_points']
          })
        })
      end
    })

    nhl_league_representation = base['leagues'].detect do |league|
      league['id'] == 'NHL'
    end

    current_season_representation = nhl_league_representation['current_season']
    rankings_representation = follow_link :relation => 'rankings', :on => current_season_representation
    rankings = rankings_representation['rankings'].map do |ranking|
      OpenStruct.new(ranking)
    end

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
    haml :index, :locals => {:games => interesting_games, :config => config, :me => me, :rankings => rankings}
  end

  get "/match" do
    match_url = params[:match_url]
    match_representation = get_url(match_url)
    match_hash = match_representation['match']

    match = OpenStruct.new({
            :home_team => match_hash['home_team']['name'],
            :home_short => match_hash['home_team']['short_name'],
            :away_team => match_hash['away_team']['name'],
            :away_short => match_hash['away_team']['short_name'],
            :scheduled_start => to_date_time(match_hash['scheduled_start']),
            :end_date => to_date_time(match_hash['end_date'])
    })

    haml :'matches/show', :locals => {:match => match}
  end

  get "/team" do
    team_url = params[:team_url]
    team_representation = get_url(team_url)
    team = OpenStruct.new(team_representation)
    players_link = extract_relation_link(team_representation, 'players')
    players_representation = get_url(players_link['href'])
    team_players = players_representation['players'].map do |source_player|
      OpenStruct.new(source_player)
    end

    haml :'teams/show', :locals => {:team => team, :players => team_players}
  end

  get "/player" do
    player_url = params[:player_url]
    player_representation = get_url(player_url)
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

  get "/pups_entries_awaiting_decision" do
    entries_awaiting_decision_representation = get_url(params[:entries_awaiting_decision_url])
    next_link = "?entries_awaiting_decision_url=#{CGI::escape((extract_relation_link entries_awaiting_decision_representation, 'next')['href'])}" if (extract_relation_link entries_awaiting_decision_representation, 'next')
    prev_link = "?entries_awaiting_decision_url=#{CGI::escape((extract_relation_link entries_awaiting_decision_representation, 'prev')['href'])}" if (extract_relation_link entries_awaiting_decision_representation, 'prev')
    start_link = "?entries_awaiting_decision_url=#{CGI::escape((extract_relation_link entries_awaiting_decision_representation, 'start')['href'])}" if (extract_relation_link entries_awaiting_decision_representation, 'start')
    entries = entries_awaiting_decision_representation['entries'].map do |entry_link|
      entry_representation = get_url(entry_link['href'])
      OpenStruct.new({
        :href => entry_representation['href'],
        :front_line => entry_representation['front_line'].map do |player|
          OpenStruct.new({:first_name => player['first_name'], :last_name => player['last_name']})
        end,
        :score => entry_representation['score']
      })
    end

    haml :'pups_entries_awaiting_decision/show', :locals => {:next_link => next_link, :prev_link => prev_link, :start_link => start_link, :entries => entries}
  end

  get "/pups_decided_entries" do
    decided_entries_representation = get_url(params[:decided_entries_url])
    next_link = "?decided_entries_url=#{CGI::escape((extract_relation_link decided_entries_representation, 'next')['href'])}" if (extract_relation_link decided_entries_representation, 'next')
    prev_link = "?decided_entries_url=#{CGI::escape((extract_relation_link decided_entries_representation, 'prev')['href'])}" if (extract_relation_link decided_entries_representation, 'prev')
    start_link = "?decided_entries_url=#{CGI::escape((extract_relation_link decided_entries_representation, 'start')['href'])}" if (extract_relation_link decided_entries_representation, 'start')
    entries = decided_entries_representation['entries'].map do |entry_link|
      entry_representation = get_url(entry_link['href'])
      OpenStruct.new({
        :href => entry_representation['href'],      
        :front_line => entry_representation['front_line'].map do |player|
          OpenStruct.new({:first_name => player['first_name'], :last_name => player['last_name']})
        end,
        :score => entry_representation['score']
      })
    end

    haml :'pups_decided_entries/show', :locals => {:next_link => next_link, :prev_link => prev_link, :start_link => start_link, :entries => entries}
  end

  get "/entry" do
    entry_representation = get_url(params[:entry_url])
    rank_representation = entry_representation['rank']    
    share_rank_response = submit_form('share', :on => rank_representation)
    share_game_rank = OpenStruct.new({
      :share_url => generate_facebook_share_url(share_rank_response['href']),
      :twitter => generate_twitter_share_url(share_rank_response['twitter']['message']),
      :email => generate_email_share_tag(share_rank_response['email']['body'], share_rank_response['email']['subject'])
    })
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

    haml :entry, :locals => {:entry => entry, :share_game_rank => share_game_rank}
  end


  get "/entries" do
    entries_representation = get_url(params['game_entries_url'])

    entries = entries_representation['entries'].map do |entry_representation|
      OpenStruct.new({
              :href => entry_representation['href'],
              :rank => entry_representation['rank']['position'],
              :score => entry_representation['score'],
              :pup_display_name => entry_representation['pup_display_name']
      })
    end

    haml :entries, :locals => {:entries => entries}
  end

  get "/transactions" do
    transactions_representation = get_url(params['transactions_url'])

    transactions = transactions_representation['transactions'].map do |transaction_representation|
      OpenStruct.new({
              :amount => transaction_representation['amount']['display'],
              :status => transaction_representation['status'],
              :description => transaction_representation['description']
      })
    end

    haml :transactions, :locals => {:transactions => transactions}
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
    url.to_uri(:verify_mode => config.ssl_verify_mode, :username => config.username, :password => config.password).post(body, options).deserialise
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

  def generate_facebook_share_url(callback_url)
    unless callback_url.blank?
      "http://www.facebook.com/sharer.php?u=#{CGI.escape(callback_url)}"
    end
  end

  def generate_twitter_share_url(message)
    "http://twitter.com/home?status=#{CGI.escape(message)}" unless message.blank?
  end

  def generate_email_share_tag(email_message, email_subject)
    unless email_message.blank? || email_subject.blank?
      "mailto:?body=#{email_message}&subject=#{email_subject}"
    end
  end

end
