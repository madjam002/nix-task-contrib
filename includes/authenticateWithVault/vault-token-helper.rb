# From https://www.vaultproject.io/docs/commands/token-helper
require 'json'

unless ENV['VAULT_ADDR']
  STDERR.puts "No VAULT_ADDR environment variable set. Set it and run me again!"
  exit 100
end

begin
  tokens = JSON.parse(File.read("#{ENV['TMPDIR']}/.vault_tokens"))
rescue Errno::ENOENT => e
  # file doesn't exist so create a blank hash for it
  tokens = {}
end

case ARGV.first
when 'get'
  print tokens[ENV['VAULT_ADDR']] if tokens[ENV['VAULT_ADDR']]
  exit 0
when 'store'
  tokens[ENV['VAULT_ADDR']] = STDIN.read
when 'erase'
  tokens.delete!(ENV['VAULT_ADDR'])
end

File.open("#{ENV['TMPDIR']}/.vault_tokens", 'w') { |file| file.write(tokens.to_json) }
