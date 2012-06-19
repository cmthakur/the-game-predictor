# dev hint: shotgun login.rb

require 'sinatra'
require 'json'

require './config/data.rb'

require 'rack/cache'

configure do
  set :public_folder, Proc.new { File.join(root, "static") }
  enable :sessions

  # set :environment, :production

  if settings.environment.to_s == "production"
    use Rack::Cache, verbose: true, metastore: Dalli::Client.new, entitystore: 'file:tmp/cache/rack/body', allow_reload: false, allow_revalidate: false
    set :static_cache_control, :public
  end
end

before /\/((match\/\d\/predict)|reset_password|predictions|leaderboard|(match\/\d\/predictions))/ do
  unless logged_in?
    session[:previous_url] = request.env["REQUEST_PATH"]
    @error = "You need to be logged in to do that"
    halt haml(:login)
  end
end

before "/match/*/result" do
  unless admin?
    halt 404
  end
end

get '/' do
  unless logged_in?
    cache_control :public
    etag "home_#{Date.today > Match.last_updated.to_date ? Date.today : Match.last_updated}"
  end
  @matches_by_date = Match.all_grouped_by_kick_off_date(limit=4)
  haml :matches, layout: !request.xhr?
end


get '/schedule' do
  unless logged_in?
    cache_control :public
    etag "home_#{Date.today > Match.last_updated.to_date ? Date.today : Match.last_updated}"
  end
  @matches_by_date = Match.all(order: [:kick_off_time.desc])
  haml :matches, layout: !request.xhr?
end


get "/user/:id/predictions" do
  cache_control :public
  etag "user_#{current_user.id}_predictions_#{current_user.last_activity}"

  @predictions = current_user.predictions.sort_by{|p| p.match.kick_off_time }.reverse
  haml :predictions, layout: !request.xhr?
end


get "/leaderboard" do
  if request.xhr?
    cache_control :public
    etag "leaderboard_#{Match.last_updated}"
  end
  @grouped_users = User.all.group_by(&:points).sort_by{|k,v| k}.reverse
  haml :leaderboard, layout: !request.xhr?
end

get "/reset_password" do
  haml :reset_password, layout: !request.xhr?
end


get "/match/:id/predictions" do
  @match = Match.get(params[:id])

  if request.xhr?
    cache_control :public
    etag "match_#{params[:id]}_predictions_#{@match.updated_at}"
  end

  if @match.prediction_deadline_passed?
    @predictions = @match.predictions.sort_by{|p| p.user.email }
  else
    @predictions = []
    @error = "You can only view other's predictions after the match kicks off"
  end
  haml :match_predictions, layout: !request.xhr?
end

post "/reset_password" do
  if current_user.authenticate(params[:current_password])
    if current_user.reset_password(params[:password], params[:password_confirmation])
      redirect "/"
    end
  else
    current_user.errors.add(:password, "Current Password is not correct")
  end
  haml :reset_password
end


get '/login' do
  cache_control :public
  etag "login"

  haml :login, layout: !request.xhr?
end

post '/login' do
  where_user_came_from = session[:previous_url] || '/'
  if User.authenticate(params[:email], params[:password])
    session[:identity] = params['email']
    session.delete(:previous_url)
    redirect to where_user_came_from
  else
    @error = "Incorrect Email/Password"
    haml :login, layout: !request.xhr?
  end
end

get '/log_out' do
  session.delete(:identity)
  @error = "Logged Out"
  redirect to "/"
end


post "/match/:id/predict" do
  return_hash = {}
  match = Match.get(params[:id])
  # if there is more than 10 minutes remaining for the match to kick off then only is the user allowed to predict
  if match.competitors_not_decided?
    return_hash[:error] = "The teams for this match haven't been decided yet"
  elsif match.prediction_deadline_passed?
    return_hash[:error] = "The deadline for prediction has passed for this match."
  else
    prediction = current_user.predictions.first_or_create(match_id: match.id)
    prediction.result = params[:prediction]
    if prediction.save
      current_user.update(last_activity: DateTime.now)
      return_hash[:result] = prediction.message
    else
     return_hash[:error] = "You can't do that. Trying something naughty huh?"
    end
  end
  content_type :json
  return_hash.to_json
end

get "/match/:id/result" do
  @match = Match.get(params[:id])
  haml :result
end

post "/match/:id/result" do
  @match = Match.get(params[:id])
  team_a_score = params[:team_a].to_i
  team_b_score = params[:team_b].to_i
  if team_a_score > team_b_score
    @match.result = @match.team_a
  elsif team_b_score > team_a_score
    @match.result = @match.team_b
  else
    @match.result = "Draw"
  end
  @match.score = "#{team_a_score} - #{team_b_score}"
  if @match.save
    @match.predictions.all(:result.not => @match.result).update(correct: false)
    @match.predictions.all(result: @match.result).update(correct: true)
    redirect to "/schedule"
  else
    @error = "Score could not be updated"
    haml :result
  end
end

helpers do
  def current_user
    session[:identity].nil? ? nil : (@user ||= User.first(email: session[:identity]))
  end

  def logged_in?
    !current_user.nil?
  end

  def country_flag_image(country_name)
    "images/#{country_name[0..2].upcase}.png"
  end

  def admin?
    logged_in? && current_user.admin?
  end
end