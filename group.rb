
require 'rest_client'
require 'json'
$LOAD_PATH << '.'
require 'mooc'
require 'pp'


ENV['MAILGUN_API_KEY'] = "key-4kkoysznhb93d1hn8r37s661fgrud-66"
RestClient.log = 'restclient.log'


class UserGroup
  attr_accessor :timezone
  attr_reader :users, :max_size, :errors

  def initialize(size, timezone = nil)
    @users = []
    @errors = []
    @max_size = size.to_i
    @timezone = timezone.to_s
  end

  def add_user(user, *options)
    @errors = []
    @errors << :already_full unless valid_size?(user, *options) 
    @errors << :bad_timezone unless valid_timezone?(user, *options)
    return false unless @errors.empty?
    @users << user
    true
  end

  def valid_size?(user, *options)
    if current_size < @max_size
      true
    elsif options.include? :ignore_full
      true
    else
      false
    end
  end

  def valid_timezone?(user, *options)
    if @users.empty? && @timezone == nil
      @timezone = user.timezone.to_s
      true
    elsif @timezone == user.timezone
      true
    # if the user is on the same continent
    elsif options.include?(:match_continents) &&
          @timezone.split('/').first == user.timezone.split('/').first
      true
    elsif options.include?(:workaround_zones)
       # best match for the azores is portugal which is in the london time zone
       user.timezone == "Atlantic/Azores" && @timezone == "Europe/London" ? true : false
    else
      # puts user.timezone.split('/').first
      false
    end
  end
  
  def current_size
    @users.size
  end
end


class UserGroupFinder
  attr_accessor :groups_to_make, :minimum_group_size, :users_to_group
  attr_accessor :match_strategy, :cumulative_strategy, :exclude_emails
  attr_reader   :groupless_users
  
  def initialize(groups_to_make = nil, users = nil, minimum_group_size = nil)
    @current_groups = []
    @groups_to_make = groups_to_make
    @users_to_group = users
    @minimum_group_size = minimum_group_size
    @match_strategy = []
    @cumulative_strategy = false
  end

  def group!
    exclude_emails!
    shuffle_users!
    @users_to_group.each do |user|
      create_new_group_for(user) unless find_group_for(user)
    end
    fold_small_groups!
  end

  def results(sort = nil)
    return @current_groups unless sort.is_a? Symbol
    @current_groups.sort_by(&sort)
  end

  def results_to_file(file_name, sort = nil)
    open(file_name, 'w') do |file|
      file.puts "Total Groups: " + @current_groups.size.to_s
      @current_groups.uniq(&:current_size).each do |group|
        file.puts "\tGroups with " + group.current_size.to_s + " members: " + 
                   @current_groups.select{|g| g.current_size == group.current_size}.size.to_s
      end
      file.puts "Total Users to Group: " + @users_to_group.size.to_s
      file.puts "Total Grouped Users: " + @current_groups.inject(0){|sum, g| sum + g.users.size }.to_s
      file.puts "Unique Timezone Groups: " + @current_groups.collect(&:timezone).uniq.count.to_s
      file.puts "Unique Timezone Users: " + @users_to_group.collect(&:timezone).uniq.count.to_s
      results(sort).each_with_index do |group, index|
        file.puts "\nGroup " + (index + 1).to_s
        file.puts "\tMax Size: " + group.max_size.to_s
        file.puts "\tCurrent Size: " + group.current_size.to_s
        file.puts "\tTimezone: " + group.timezone
        file.puts "\tUsers:"
        group.users.each do |user|
          file.puts "\t\tUser " + user.id.to_s + ": \t\t" + 
                    [user.email, user.timezone, user.expertise].join(", ")
        end
      end
    end
  end

  def results_to_db_and_create_lists!
    @current_groups.each do |group|
      dm_group = Group.new
      dm_group.users = group.users
      dm_group.timezone = group.timezone
      dm_group.save
    end
  end

  private

  def exclude_emails!
    return @users_to_group unless @exclude_emails
    @users_to_group.delete_if{|u| @exclude_emails.collect(&:upcase).include? u.email.upcase }
  end

  def fold_small_groups!
    return unless @minimum_group_size
    small_groups = @current_groups.select{|g| g.current_size < @minimum_group_size}
    @current_groups = @current_groups - small_groups
    @groupless_users = small_groups.collect(&:users).flatten
    match_strategy(0)
  end

  def match_strategy(level)
    unless @match_strategy[level]
      puts "Could not match all users to groups!"
      pp @groupless_users
      # return false
    end
    if level % 14 == 0 
      puts "GS: " + @current_groups.count.to_s
      create_new_group_for(@groupless_users.first) 
    end
    current_options = @cumulative_strategy ? @match_strategy[0..level] : @match_strategy[level]
    @groupless_users.delete_if{|user| find_group_for(user, *current_options)}
    match_strategy(level + 1) unless @groupless_users.empty?
  end

  def find_group_for(user, *options)
    @current_groups.shuffle! 
    @current_groups.each do |group|
      if group.add_user(user, *options)
        # puts "Found existing group for " + user.inspect
        return true
      end
    end
    false
  end

  def create_new_group_for(user)    
    new_size = available_group_sizes.shuffle.first
    group = UserGroup.new(new_size, user.timezone)
    group.add_user(user)
    @current_groups << group
    # puts "Created new group for user " + user.inspect
  end

  def available_group_sizes
    current_group_sizes = {}
    @current_groups.uniq(&:max_size).each do |group|
      current_group_sizes[group.max_size] =  @current_groups.select{|g| g.max_size == group.max_size}.size
    end
    available_groups = @groups_to_make.keys
    current_group_sizes.each_pair do |group_size, number_of_groups|
      available_groups.delete(group_size.to_s) if number_of_groups.to_i >= @groups_to_make[group_size.to_s].to_i
    end
    available_groups
  end

  def shuffle_users!
    # shuffle the deck of users 7 times. Poker pays off
    7.times{ @users_to_group.shuffle! }
  end

end


##################################################################################################
#
#  get_unsubscribes! updates the local database with the unsubscribe data from mailgun
#
##################################################################################################


def get_unsubscribes!
  unsubs = JSON.parse RestClient.get("https://api:#{ENV['MAILGUN_API_KEY']}" \
                                     "@api.mailgun.net/v2/mechanicalmooc.org/unsubscribes?limit=1000")
  # puts unsubs
  unsubscribers_mailgun = unsubs["items"]
  unsubscribers_mailgun.each do |unsub_mailgun|
    u = User.first(:conditions => ["UPPER(email) = ?", unsub_mailgun["address"].upcase])
    if u
      u.unsubscribed = true
      u.unsubscribed_at = unsub_mailgun["created_at"]
      u.save
      # puts u.inspect
    else
      puts "NOT IN DB: " + unsub_mailgun["address"]
    end
  end
end

def get_logs!
  unsubs = JSON.parse RestClient.get("https://api:#{ENV['MAILGUN_API_KEY']}" \
                                     "@api.mailgun.net/v2/mechanicalmooc.org/log?limit=1000")
  open('mechmoocorg.log', 'w') do |f|
    f.puts JSON.pretty_generate(unsubs)
  end
  

end

def post_stuff!
  RestClient.post("http://localhost:4567/mooc-mailgun-log", :domain => "hajima", :stuff => "hello")
end

##################################################################################################
# This is old code

# total = users_available_to_group.count
# puts total

# Assuming equal number of groups for each group size
# (x * 12) + (x * 6) + (x * 3) = total
# number_of_groups = (total / 21).floor

# We want 242 groups of 3, 242 groups of 6, and 242 groups of 12
# groups_to_make = Hash['3' => 242, '6' => 242, '12' => 242, '100' => 1]
# puts groups_to_make.inspect
# group_users(groups_to_make)

##################################################################################################



get_unsubscribes!
# exit

def users_available_to_group
  User.all(:unsubscribed => false, :group_work => true, :round => 2)
end

def try_to_group
  placer = UserGroupFinder.new
  placer.groups_to_make = {'40' => 242, '90' => 242}
  placer.users_to_group = users_available_to_group
  # placer.exclude_emails = ["thaw.htaiK@gmail.com", "brynkng@gmail.com"]
  placer.minimum_group_size = 24
  placer.cumulative_strategy = true
  placer.match_strategy = [:workaround_zones, :match_continents] #, :ignore_full]
  placer.group!
  if placer.groupless_users.empty?
    puts "Got everyone ;-)"
    placer.results_to_file('seq2-new-groups.txt', :timezone)
    placer.results_to_db_and_create_lists!
    exit
  else
    try_to_group
  end
end

try_to_group

# Messages sent between groups



