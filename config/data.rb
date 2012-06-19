require 'data_mapper'
require 'bcrypt'


DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/development.db")

class Match
  include DataMapper::Resource

  TEAMS = [
    "Croatia",
    "Czech Republic",
    "Denmark",
    "England",
    "France",
    "Germany",
    "Greece",
    "Italy",
    "Netherlands",
    "Poland",
    "Portugal",
    "Republic of Ireland",
    "Russia",
    "Spain",
    "Sweden",
    "Ukraine"
  ]

  property :id, Serial
  property :team_a, String, required: true, set: [*TEAMS, "TBD"]
  property :team_b, String, required: true, set: [*TEAMS, "TBD"]
  property :kick_off_date, Date, required: true
  property :kick_off_time, DateTime, required: true
  property :group, String
  property :score, String
  property :result, String

  timestamps :created_at, :updated_at

  has n, :predictions

  def kick_off_time=(time)
    self[:kick_off_time] = time.is_a?(String) ? DateTime.strptime("#{time} +0000", "%m/%d %H:%M %z") : time
    self[:kick_off_date] = self[:kick_off_time].to_date
    self[:kick_off_time]
  end


  def nepali_kick_off_time
    self.kick_off_time + (4.75/24.0) # add 4:45 to the actual time
  end

  def competitors_not_decided?
    [self.team_a, self.team_b].include?("TBD")
  end

  # if the deadline for prediction has passed
  def prediction_deadline_passed?
    ((self.kick_off_time - relative_current_time) * 24 * 60).to_f <= 15
  end


  def open_for_prediction?
    !prediction_deadline_passed? && !competitors_not_decided?
  end

  def completed?
    relative_current_time > (self.kick_off_time + 2.0/24)
  end

  # since all kick_off_times are stored with the default time zone which should be in UTC
  # hacked method to return the relative current time in utc
  def relative_current_time
    # server is -8:00 from UTC so add 8 hours to current time
    DateTime.now + 8.0/24
  end

  after :save do |match|
    match.class.last_updated = Time.now
  end

  class << self
    attr_accessor :last_updated

    def all_grouped_by_kick_off_date(limit = nil)
      options = { :kick_off_date.lte => Date.today, order: [:kick_off_time.desc] }
      options[:limit] = limit if limit
      all(options)#.group_by(&:kick_off_date)
    end
  end

  self.last_updated = Time.now

end


class User
  include DataMapper::Resource

  attr_accessor :password, :password_confirmation

  timestamps :created_at, :updated_at

  property :id, Serial
  property :crypted_pass, String, length: 60..60, required: true, writer: :protected
  property :email, String, length: 5..200, required: true, format: :email_address, unique: true
  property :admin, Boolean, default: false
  property :last_activity, DateTime, default: DateTime.now

  has n, :predictions

  validates_presence_of :password, :password_confirmation, :if => :password_required?
  validates_confirmation_of :password, :if => :password_required?

  before :valid?, :crypt_password

  alias :admin? :admin

  # check validity of password if we have a new resource, or there is a plaintext password provided
  def password_required?
    new? or password
  end

  def reset_password(password, confirmation)
    update(:password => password, :password_confirmation => confirmation)
  end

  # Hash the password using BCrypt
  #
  # BCrypt is a lot more secure than a hash made for speed such as the SHA algorithm. BCrypt also
  # takes care of adding a salt before hashing.  The whole thing is encoded in a string 60 bytes long.
  def crypt_password
    self.crypted_pass = BCrypt::Password.create(password) if password
  end

  # Prepare a BCrypt hash from the stored password, overriding the default reader
  #
  # return the `:no_password` symbol if the property has no content.  This is for
  # the safety of the authenticate method.  It's easy to pass a nil password to
  # that method, but passing a specific symbol takes effort.
  def crypted_pass
    pass = super
    if pass
      BCrypt::Password.new(pass)
    else
      :no_password
    end
  end

  def authenticate(password)
    crypted_pass == password
  end

  def self.authenticate(email, password)
    email = email.to_s.downcase
    u = first(:conditions => ['lower(email) = ?', email])
    if u && u.authenticate(password)
      u
    else
      nil
    end
  end


  # the prediction for the match
  def prediction_for(match)
    self.predictions.first(match_id: match.id)
  end

  def points
    @point ||= self.predictions.all(correct: true).count
  end

  def name
    self.email.split("@").first.strip
  end

end


class Prediction
  include DataMapper::Resource

  property :id, Serial
  property :result, String, required: true, set: [*Match::TEAMS, "Draw"]
  property :correct, Boolean, default: false

  timestamps :created_at, :updated_at

  belongs_to :match
  belongs_to :user

  alias :correct? :correct

  def message
    case self.result
    when "Draw"; "You predicted this match will be a draw"
    else; "You predicted #{self.result} will win this match"
    end
  end



  def short_message
    "#{%w(certainly definitely undoubtedly indubitably unquestionably)[rand(5)]} #{self.result}"
  end
end

DataMapper.finalize


DataMapper.auto_upgrade!