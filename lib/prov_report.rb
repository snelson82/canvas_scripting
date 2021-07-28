require 'csv'
require 'zip'
require 'json'
require 'typhoeus'
require 'fileutils'

module ProvisioningReport
  def self.user_report(domain)
    headers = { authorization: "Bearer #{ENV['SA_TOKEN']}" }
    url = "https://#{domain}.instructure.com/api/v1/accounts/self/reports/provisioning_csv"

    request = Typhoeus::Request.new(
      url,
      headers: headers,
      method: :post,
      body: {
        parameters: {
          users: true,
          enrollment_term_id: ''
        }
      }
    )
    request.on_complete do |response|
      data = JSON.parse(response.body)
      if response.success?
        sleep(5)
        user_report_status(domain, data['id'])
      else
        puts "Error: #{response.code}"
      end
    end
    request.run
  end

  def self.user_report_status(domain, report_id)
    headers = { 'Authorization' => "Bearer #{ENV['SA_TOKEN']}" }
    url = "https://#{domain}.instructure.com/api/v1/accounts/self/reports/provisioning_csv/#{report_id}"

    request = Typhoeus::Request.new(url, headers: headers)
    request.on_complete do |response|
      data = JSON.parse(response.body)
      if data['progress'] < 100
        sleep(5)
        user_report_status(domain, report_id)
      elsif data['progress'] == 100 && data['status'] == 'complete'
        user_report_download(data['attachment']['url'], "#{domain}_users.csv")
      else
        puts 'Not sure what happened'
      end
    end
    request.run
  end

  def self.user_report_download(download_url, filename)
    downloaded_file = File.open(File.expand_path("./#{filename}", 'user_data'), 'wb')
    headers = { 'Authorization' => "Bearer #{ENV['SA_TOKEN']}" }

    request = Typhoeus::Request.new(download_url, headers: headers, method: :get, followlocation: true)

    request.on_body do |chunk|
      downloaded_file.write(chunk)
    end

    request.on_complete do |_response|
      downloaded_file.close
    end
    request.run
  end

  def self.enrollments_report(domain)
    headers = { 'Authorization' => "Bearer #{ENV['SA_TOKEN']}" }
    url = "https://#{domain}.instructure.com/api/v1/accounts/self/reports/provisioning_csv"

    request = Typhoeus::Request.new(
      url,
      headers: headers,
      method: :post,
      body: {
        parameters: {
          enrollments: true,
          enrollment_term_id: ''
        }
      }
    )
    request.on_complete do |response|
      data = JSON.parse(response.body)
      if response.success?
        sleep(5)
        enrollments_report_status(domain, data['id'])
      else
        puts "Error: #{response.code}"
      end
    end
    request.run
  end

  def self.enrollments_report_status(domain, report_id)
    headers = { 'Authorization' => "Bearer #{ENV['SA_TOKEN']}" }
    url = "https://#{domain}.instructure.com/api/v1/accounts/self/reports/provisioning_csv/#{report_id}"

    request = Typhoeus::Request.new(url, headers: headers)
    request.on_complete do |response|
      data = JSON.parse(response.body)
      if data['progress'] < 100
        sleep(5)
        enrollments_report_status(domain, report_id)
      elsif data['progress'] == 100 && data['status'] == 'complete'
        enrollments_report_download(domain, data['attachment']['url'], "#{domain}_enrollments.csv")
      else
        puts 'Not sure what happened'
      end
    end
    request.run
  end

  def self.enrollments_report_download(_domain, download_url, filename)
    downloaded_file = File.open(File.expand_path("./#{filename}", 'user_data'), 'wb')
    headers = { 'Authorization' => "Bearer #{ENV['SA_TOKEN']}" }

    request = Typhoeus::Request.new(download_url, headers: headers, method: :get, followlocation: true)

    request.on_body do |chunk|
      downloaded_file.write(chunk)
    end

    request.on_complete do |_response|
      downloaded_file.close
    end
    request.run
  end

  def self.extract_zip(file, destination)
    FileUtils.mkdir_p(destination)
    Zip::File.open(file) do |zip_file|
      zip_file.each do |single_file|
        file_path = File.join(destination, single_file.name)
        zip_file.extract(single_file, file_path) unless File.exist?(file_path)
      end
    end
  end
end
