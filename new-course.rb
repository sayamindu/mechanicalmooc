

$list_address = ''
if ARGV[0].nil? || ARGV[0].length < 3
  puts "Takes the new list name as an argument"
  puts "Will then add all the users to the list"
  exit
else
 list_address = ARGV[0]   
 puts "Making list with all users - " + list_address
 puts "Remember to set access level to read only"
end

require 'rest_client'
$LOAD_PATH << '.'
require 'mooc'



ENV['MAILGUN_API_KEY'] = "key-4kkoysznhb93d1hn8r37s661fgrud-66"

def start_list_with_name(list_address)
  RestClient.post("https://api:#{ENV['MAILGUN_API_KEY']}" \
                  "@api.mailgun.net/v2/lists",
                  :address => list_address,
                  :access_level => 'members')
  RestClient.post("https://api:#{ENV['MAILGUN_API_KEY']}" \
                  "@api.mailgun.net/v2/lists/#{list_address}/members",
                  :address => "the-machine@mechanicalmooc.org",
                  :upsert => 'yes')
end



def add_all_user_to_list(list_address)
  users = User.all
  puts users.count
  users.each do |u|
    # puts u.email
    RestClient.post("https://api:#{ENV['MAILGUN_API_KEY']}" \
                    "@api.mailgun.net/v2/lists/#{list_address}/members",
                    :address => u.email,
                    :upsert => 'yes')
  end
end

start_list_with_name($list_name)
add_all_user_to_list($list_name)

