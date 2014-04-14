require 'http_router'
require 'yaml'
require 'hashie'
require 'ipaddr'
require 'multi_json'
require 'rack/fiber_pool'
require 'logger'
require 'em-synchrony'

config = Hashie::Mash.new(YAML.load_file('config.yml'))
router = HttpRouter.new()
logger = Logger.new('output.log')

@valid_remote_addr = (config.ip_restrictions || []).map(){ |ip| IPAddr.new(ip) }

@secure_ip = {}

def ip_address_valid?(ip)
  @secure_ip[ip] ||= @valid_remote_addr.find(-> { false }) {|ipaddr| ipaddr.include?(ip) }
end

def parse_bitbucket_request(body)
  json = Hashie::Mash.new(MultiJson.load(body))

  branches = (json[:commits] || []).map(&:branch).uniq
  {
    branches: branches,

  }
end

def parse_github_request(body)

end

router.add('/:app_name') do |env|
  next [401,{},[]] unless ip_address_valid?(env['REMOTE_ADDR'])
  params = env['router.params']

  next [404,{},[]] unless @app = config.watch[params[:app_name]]

  logger.info "Requesting #{params[:app_name]}"

  @app

  type = @app[:type]

  request = send("parse_#{type}_request", env['rack.input'].read)

  if request[:branches].include?(@app.branch)
    logger.info "Fetching #{@app.branch} branch"
    output = []
    EventMachine::Synchrony.defer do
      output = `cd #{@app.path}`.split("\n") + `git pull`.split("\n")
    end
    output.each { |line| logger.info(line) }
  end
end

use Rack::FiberPool

run router