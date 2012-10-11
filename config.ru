$stdout.sync = true # See stdout logs in `heroku logs`

require './mooc'
run Sinatra::Application
