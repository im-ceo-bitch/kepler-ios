#!/usr/bin/env ruby
# Read ONLY current version from App Store Connect; default build number 200.
require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

def b64(s); Base64.urlsafe_encode64(s, padding: false); end
key = OpenSSL::PKey.read(File.read(ENV.fetch('ASC_P8_PATH')))
now = Time.now.to_i
hdr = {alg:'ES256', kid:ENV.fetch('ASC_KEY_ID'), typ:'JWT'}
payload = {iss:ENV.fetch('ASC_ISSUER_ID'),iat:now,exp:now+900,aud:'appstoreconnect-v1'}
unsigned = "#{b64(JSON.generate(hdr))}.#{b64(JSON.generate(payload))}"
der = key.sign(OpenSSL::Digest.new('SHA256'), unsigned)
raw = OpenSSL::ASN1.decode(der).value.map{|v| v.value.to_s(2).rjust(32, "\x00")}.join
token = "#{unsigned}.#{b64(raw)}"

def get_json(path, token)
  uri = URI(path)
  raise 'Unsafe host' unless uri.scheme=='https' && uri.host=='api.appstoreconnect.apple.com'
  for attempt in 0..3
    resp = Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:15,read_timeout:30) do |h|
      h.get(uri.request_uri, {'Authorization'=>"Bearer #{token}",'Accept'=>'application/json'})
    end
    if [429,500,502,503,504].include?(resp.code.to_i) && attempt<3
      sleep(2**attempt); next
    end
    raise "Apple API HTTP #{resp.code}: #{resp.body.to_s[0,500]}" unless resp.code.to_i==200
    return JSON.parse(resp.body)
  end
end

def pages(url,token)
  rows=[]; count=0
  while url
    data=get_json(url,token)
    rows.concat(data.fetch('data'))
    url=data.fetch('links',{})['next']
    count+=1
    raise 'Too many pagination requests' if count>100
  end
  rows
end
version=ENV.fetch('MARKETING_VERSION')
raise 'Invalid version' unless version.match?(/\A\d+\.\d+\.\d+\z/)
apps=pages('https://api.appstoreconnect.apple.com/v1/apps?filter%5BbundleId%5D=com.iumrah.app&limit=200',token)
app=apps.find{|a| a.dig('attributes','bundleId')=='com.iumrah.app'}
raise 'Transferred app not found in NEW App Store Connect key' unless app
raise "Wrong App ID (#{app['id']})" unless app['id']=='6759577859'
pre=pages("https://api.appstoreconnect.apple.com/v1/apps/#{app['id']}/preReleaseVersions?limit=200",token)
matches=pre.select{|e| e.dig('attributes','version')==version && e.dig('attributes','platform')=='IOS'}
raise 'Duplicate preReleaseVersions detected' if matches.length>1
versions=[]
if !matches.empty?
  rows=pages("https://api.appstoreconnect.apple.com/v1/preReleaseVersions/#{matches[0]['id']}/builds?limit=200",token)
  versions=rows.filter_map do |row|
    num=row.dig('attributes','version').to_s
    Integer(num) if num.match?(/\A[1-9]\d*\z/)
  end
end
number=[200,(versions.max||199)+1].max
raise "Build number #{number} unexpectedly high; stop" unless (200..4999).include?(number)
File.open(ENV.fetch('GITHUB_ENV'),'a'){|f| f.puts "BUILD_NUMBER=#{number}"}
puts "Confirmed APP #{app['id']} from NEW team; TestFlight version #{version}; next build #{number}"
