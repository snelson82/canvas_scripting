# WORKING AS OF 06-22-2021
require 'csv'
require 'json'
require 'typhoeus'
require 'io/console'

### Prompts to set ENV, DOMAIN, TOKEN, and CSV FILE PATH

## ENV
puts "For prod, hit enter. For Beta, enter 'beta'. For Test, enter 'test'"
env = gets.chomp!.downcase
env != '' ? env << '.' : env

## DOMAIN
puts 'Enter the domain, EX: <domain>.instructure.com'
domain = gets.chomp!.downcase
# domain = ''

## TOKEN
puts 'Enter a valid access token to perform the API calls within this script'
$token = $stdin.noecho(&:gets).chomp!

## CSV FILE
puts 'Enter the full file path for CSV data. EX: /Users/person/file/to/path.csv'
$csv_file = gets.chomp!

raise "Can't locate the CSV file." unless File.exist?($csv_file)

$base_url = "https://#{domain}.#{env}instructure.com/api/v1/"
$hydra = Typhoeus::Hydra.new(max_concurrency: 10)

CSV.foreach($csv_file, headers: true) do |row|
  next if row['email'].empty? || row['email'].nil?

  raise 'Valid CSV headers not found (Expecting user_id,email)' if row['user_id'].nil? || row['email'].nil?

  request = Typhoeus::Request.new(
    "#{$base_url}/users/sis_user_id:#{row['user_id']}",
    method: :put,
    headers: {
      authorization: "Bearer #{$token}"
    },
    body: {
      user: {
        email: row['email'].to_s
      }
    }
  )
  request.on_complete do |response|
    data = JSON.parse(response.body)
    puts "edit user data: \n#{data['email']}" unless data['email']&.to_s == row['email']&.to_s

    if response.success?
      puts "Successfully updated user #{row['user_id']}'s email address (#{response.code})"
    elsif response.timed_out?
      puts "ERROR: There was an issue processing user #{row['user_id']}'s email (#{response.code})"
    elsif response.code.zero?
      puts "ERROR: #{response.return_message}"
    else
      "HTTP request failed: #{response.code}"
    end
    sleep(0.2) if response.headers['X-Rate-Limit-Remaining'].to_i <= 200
  end
  $hydra.queue(request)
end

$hydra.run
