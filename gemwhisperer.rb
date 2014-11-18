# encoding: utf-8

require 'sinatra'
require 'active_record'
require 'twitter'
require 'json'

require 'yaml'
require 'logger'
require 'digest/sha2'
require 'net/http'
require 'uri'

if File.exist?('config/application.yml')
  config = YAML.load_file('config/application.yml')
  config.each{|k,v| ENV[k] = v }
end

Twitter.configure do |config|
  config.consumer_key       = ENV['CONSUMER_KEY']
  config.consumer_secret    = ENV['CONSUMER_SECRET']
  config.oauth_token        = ENV['REQUEST_TOKEN']
  config.oauth_token_secret = ENV['REQUEST_SECRET']
end

configure do
  Log = Logger.new(STDOUT)
  Log.level = Logger::INFO
  ActiveRecord::Base.logger = Log
end

set :root, File.dirname(__FILE__)

configure :development do
  require 'sqlite3'

  ActiveRecord::Base.establish_connection(
    :adapter  => 'sqlite3',
    :database => 'db/development.db'
  )
end

configure :production do
  creds = YAML.load(ERB.new(File.read('config/database.yml')).result)['production']
  ActiveRecord::Base.establish_connection(creds)
end

class Whisper < ActiveRecord::Base
  def self.trim_table
    connection.execute <<-SQL
DELETE FROM whispers
WHERE id NOT IN (SELECT id FROM whispers ORDER BY created_at DESC LIMIT 50);
    SQL
  end
end

get '/' do
  @whispers = Whisper.order('created_at DESC').limit(25)
  erb :index
end

post '/hook' do
  data = request.body.read
  Log.info "got webhook: #{data}"

  hash = JSON.parse(data)
  Log.info "parsed json: #{hash.inspect}"

  authorization = Digest::SHA2.hexdigest(hash['name'] + hash['version'] + ENV['RUBYGEMS_API_KEY'])
  if env['HTTP_AUTHORIZATION'] == authorization
    Log.info "authorized: #{env['HTTP_AUTHORIZATION']}"
  else
    Log.info "unauthorized: #{env['HTTP_AUTHORIZATION']}"
    error 401
  end

  whisper = Whisper.create(
    :name    => hash['name'],
    :version => hash['version'],
    :url     => hash['project_uri'],
    :info    => hash['info']
  )

  Whisper.trim_table

  Log.info "created whisper: #{whisper.inspect}"

  if hash['metadata']['changelog'] && hash['metadata']['changelog'].length > 20
    whisper_text = whisper_text_changelog(whisper, hash['metadata']['changelog'])
  else
    whisper_text = whisper_text_generic(whisper)
  end

  $stderr.puts(whisper_text.inspect)
  $stderr.puts(whisper_text.length)

  response = Twitter.update(whisper_text)
  Log.info "TWEETED! #{response}"
end

def whisper_text_generic(whisper)
  suffix     = " | gems by @plexus"
  max_length = 140 - suffix.length - 23  # Twitter counts 21-23 chars per link

  whisper_text = "#{whisper.name} #{whisper.version} has been released! %s #{whisper.info}"
  whisper_text = truncate(whisper_text) % whisper.url

  whisper_text + suffix
end

def whisper_text_changelog(whisper, changelog)
  truncate("#{whisper.name} #{whisper.version} released! %s #{changelog}") % whisper.url
end

def truncate(str, max_length)
  if str.length > max_length
    str.chars.take(max_length).join + '…'
  else
    str
  end
end
