version = '20180606-1'
require 'optparse'
require 'csv'
require 'YAML'
def writecsv(filename, headers, data, use_sym, change_headers)
  csv = CSV.open("#{filename}.csv", 'wb')
  use_headers = []
  if change_headers
    headers.each do |header|
      if change_headers[header]
        use_headers.push(change_headers[header])
      else
        use_headers.push(header)
      end
    end
  else
    use_headers = headers
  end
  csv << use_headers
  data.each do |row|
    out = []
    headers.each do |header|
      out << if use_sym
               row[header.to_sym]
             else
               row[header]
             end
    end
    csv << out
  end
  csv.close
end

options = {}
parse = OptionParser.new do |opts|
  opts.banner = 'Usage: script.rb [options]'
  opts.on('-c', '--client CLIENT_ALIAS', String, 'Alias for client. Other field not required when provided. (required)') do |a|
    if File.directory?(a) && File.exist?("#{a}/#{a}.yaml")
      options = YAML.load_file("#{a}/#{a}.yaml")
    else
      (puts 'ERROR: Client does not exist!')
    end
  end
  opts.on('-l', '--canvasfile [FILENAME]', String, 'Input SIS export CSV file (required)') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    puts '-s hit'
    File.exist?(a) ? (options[:canvas] = a) : (puts 'ERROR: Canvas SIS export user CSV file does not exist!')
  end
  opts.on('-p', '--psfile [FILENAME]', String, 'Input SIS App From PowerSchool staff export CSV file (required)') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:sisapp] = a) : (puts 'ERROR: SIS App staff CSV file does not exist!')
  end
  opts.on('-k', '--kimonofile [FILENAME]', String, 'Input Kimono PowerSchool staff export CSV file (required)') do |a|
    a = "#{options[:client]}/#{a}" unless options[:client].nil?
    File.exist?(a) ? (options[:kimono] = a) : (puts 'ERROR: Kimono export CSV file does not exist!')
  end
  opts.on_tail('-h', '--help', "Show this message (#{version})") do
    puts opts
    exit
  end
end.parse!
if options[:client].nil?
  puts "ERROR: Client is required!\nUse -h for help.\n\n"
  exit
end
if options[:kimono].nil?
  options[:kimono] = "#{options[:client]}/kimonostaffexport.csv"
  unless File.exist?(options[:kimono])
    puts 'ERROR: Kimono filename not provided and default name does not exists!'
    exit
  end
end
if options[:sisapp].nil?
  options[:sisapp] = "#{options[:client]}/staff.csv"
  unless File.exist?(options[:sisapp])
    puts 'ERROR: PowerSchool file from SISApp filename not provided and default name does not exists!'
    exit
  end
end
if options[:canvas].nil?
  options[:canvas] = "#{options[:client]}/canvasuserprovisioning.csv"
  unless File.exist?(options[:canvas])
    puts 'Warning: Canvas user export filename not provided and default filename does not exists. Downloading report...'
    system("ruby ./get_prov_report.rb -c #{options[:client]} -f canvasuserprovisioning.csv")
    unless File.exist?(options[:canvas])
      puts 'ERROR: Canvas user SIS Export filename not provided and unable to download the file!'
      exit
    end
  end
end

analysisdir = "#{options[:client]}/analysis"
Dir.mkdir(analysisdir) unless Dir.exist?(analysisdir)

puts 'Loading SIS App Data...'
sisapp = {}
CSV.foreach(options[:sisapp], headers: true) do |row|
  sisapp['staff_' + row['id']] = row
end

puts 'Loading Kimono Data...'

kimono_headers = []
# Build comparison hashes
kimono_id = {}
kimono_lid = {}
duplicate_local_id = {}
duplicate_local_id_data = []
CSV.foreach(options[:kimono], headers: true) do |row|
  kimono_headers = row.headers if kimono_headers.empty?
  kimono_id[row['legacy_sis_user_id']] = row
  if kimono_lid[row['local_id']].nil? && duplicate_local_id[row['local_id']].nil?
    kimono_lid[row['local_id']] = row
  elsif duplicate_local_id[row['local_id']].nil?
    duplicate_local_id[row['local_id']] = [row['sis_user_id']]
    this_data = {}
    that_data = {}
    puts "   duplicate Kimono local_id (#{row['local_id']})"
    kimono_headers.each do |header|
      this_data[header.to_sym] = row[header]
      that_data[header.to_sym] = kimono_lid[row['local_id']][header]
    end
    duplicate_local_id_data << that_data
    duplicate_local_id_data << this_data
    kimono_lid[row['local_id']] = 'error'
  else
    duplicate_local_id[row['local_id']] << row['sis_user_id']
    this_data = {}
    puts "   duplicate Kimono local_id (#{row['local_id']})"
    kimono_headers.each do |header|
      this_data[header.to_sym] = row[header]
    end
    duplicate_local_id_data << this_data
  end
end
canvas_headers = []
remap_data = []
unknown_data = []
unmatched_data = []
CSV.foreach(options[:canvas], headers: true) do |row|
  id = ''
  canvas_headers = row.headers if canvas_headers.empty?
  if row['user_id'].nil?
    parts = ['']
  elsif row['user_id'].match(/^stf\d+$/)
    parts = ['staff']
    id = row['user_id'].sub('stf', 'staff_')
  #  puts "match on staff #{row['user_id']}"
  #  exit
  else
    parts = row['user_id'].split('_')
  end

  case parts[0]
  when 'staff', 'stf'
    puts "Working on staff: #{row['user_id']}"
    id = row['user_id'] if id == ''
    login_id = row['login_id'].nil? ? '' : row['login_id'].downcase
    # try to get user's local_id
    defined?(sisapp[id]) && !sisapp[id].nil? ? (sisapp_local_id = sisapp[id]['local_id']) : (sisapp_local_id = '')
    not_matched = true
    match_data = {}
    # Section checks current line against the predicted Kimono legacy user_id
    if defined?(kimono_id[id])
      # try to get Kimono login_id
      defined?(kimono_id[id]['login_id']) && !kimono_id[id]['login_id'].nil? ? (klogin_id = kimono_id[id]['login_id'].downcase) : (klogin_id = '')
      # try to get Kimono local_id
      defined?(kimono_id[id]['local_id']) && !kimono_id[id]['local_id'].nil? ? (klocal_id = kimono_id[id]['local_id']) : (klocal_id = '')
      # get Kimono and SISApp name
      defined?(kimono_id[id]['first_name']) && defined?(kimono_id[id]['last_name']) && !kimono_id[id]['last_name'].nil? && !kimono_id[id]['first_name'].nil? ? (kname = "#{kimono_id[id]['first_name']}~#{kimono_id[id]['last_name']}") : (kname = '')
      defined?(sisapp[id]['name.first_name']) && defined?(sisapp[id]['name.last_name']) && !sisapp[id]['name.last_name'].nil? && !sisapp[id]['name.first_name'].nil? ? (sname = "#{sisapp[id]['name.first_name']}~#{sisapp[id]['name.last_name']}") : (sname = '')
      # puts "   #{klocal_id}=#{sisapp_local_id.strip} || #{kname}=#{sname}"
      # See if the current line matches on Kimono login_id
      if !klogin_id.empty? && login_id == klogin_id
        puts "   looks like a match (old ID and login_id), so #{row['user_id']} -> #{kimono_id[id]['sis_user_id']}"
        not_matched = false
        match_data[:method] = 'old_user_id+login_id'
        match_data[:match_data] = "#{klogin_id}=#{login_id}"
      # see if the current line matches on Kimono local_id
      elsif !klocal_id.empty? && sisapp_local_id.strip != '' && sisapp_local_id == klocal_id
        puts "   looks like a match (old ID and local_id), so #{row['user_id']} -> #{kimono_id[id]['sis_user_id']}"
        not_matched = false
        match_data[:method] = 'old_user_id+local_id'
        match_data[:match_data] = "#{klocal_id}=#{sisapp_local_id}"
      elsif kname != '' && kname == sname
        puts "   looks like a match (old ID and name), so #{row['user_id']} -> #{kimono_id[id]['sis_user_id']}"
        not_matched = false
        match_data[:method] = 'old_user_id+name'
        match_data[:match_data] = "#{kname}=#{sname}"
      end
      unless not_matched
        match_data[:old_id] = row['user_id']
        match_data[:new_id] = kimono_id[id]['sis_user_id']
        match_data[:canvas_user_id] = row['canvas_user_id']
        match_data[:canvas_login_id] = row['login_id']
      end

    end

    # If previous section fails to find a match then try to find the user with the local_id
    if not_matched && !sisapp_local_id.nil? && sisapp_local_id.strip != '' && defined?(kimono_lid[sisapp_local_id]) && !kimono_lid[sisapp_local_id].nil? && kimono_lid[sisapp_local_id] != 'error'
      # matched just on local_id at this point...let's make a coupld of other checks
      # defined?(kimono_id[id]['last_name']) && !kimono_id[id]['last_name'].nil? ? (k2last_name = kimono_id[id]['last_name']) : (k2last_name = "")
      defined?(kimono_lid[sisapp_local_id]['login_id']) && !kimono_lid[sisapp_local_id]['login_id'].nil? ? (kllogin_lid = kimono_lid[sisapp_local_id]['login_id'].downcase) : (kllogin_id = '')
      defined?(kimono_lid[sisapp_local_id]['first_name']) && defined?(kimono_lid[sisapp_local_id]['last_name']) && !kimono_lid[sisapp_local_id]['last_name'].nil? && !kimono_lid[sisapp_local_id]['first_name'].nil? ? (klname = "#{kimono_lid[sisapp_local_id]['first_name']}~#{kimono_lid[sisapp_local_id]['last_name']}") : (klname = '')
      puts "#{klname} #{kllogin_id}"
      not_matched = false
      if !kllogin_id.nil? && !klogin_id == '' && login_id == kllogin_id
        match_data[:method] = 'local_id+login_id'
        match_data[:match_data] = "#{sisapp_local_id}=#{sisapp_local_id} + #{kllogin_id}=#{login_id}"
        puts "   looks like a match (local_id+name), so #{row['user_id']} -> #{kimono_lid[sisapp_local_id]['sis_user_id']}"
      elsif sname != '' && sname == klname
        match_data[:method] = 'local_id+name'
        match_data[:match_data] = "#{sisapp_local_id}=#{sisapp_local_id} + #{klname}=#{sname}"
        puts "   looks like a match (local_id+name), so #{row['user_id']} -> #{kimono_lid[sisapp_local_id]['sis_user_id']}"
      else
        match_data[:method] = 'local_id'
        match_data[:match_data] = "#{sisapp_local_id}=#{sisapp_local_id}"
        puts "   looks like a match (only local_id), so #{row['user_id']} -> #{kimono_lid[sisapp_local_id]['sis_user_id']}"
      end

      unless not_matched
        match_data[:old_id] = id
        match_data[:new_id] = kimono_lid[sisapp_local_id]['sis_user_id']
        match_data[:canvas_user_id] = row['canvas_user_id']
        match_data[:canvas_login_id] = row['login_id']
      end
    end

    if not_matched
      this_data = {}
      puts "   user with staff_id:#{id} and local_id:#{sisapp_local_id} not in Kimono"
      canvas_headers.each do |header|
        this_data[header.to_sym] = row[header]
      end
      this_data[:unmatched_login_id] = "unmatched_-_#{this_data[:login_id]}"
      unmatched_data << this_data
    else
      match_data[:type] = 'user'
      remap_data << match_data
    end
  when 'student'
  # puts "student...skipping"
  when ''
  # puts "user with no SIS ID...skipping"
  else
    this_data = {}
    puts "unknown: #{row['user_id']}"
    canvas_headers.each do |header|
      this_data[header.to_sym] = row[header]
    end
    unknown_data << this_data
  end
end
unmatched_headers = canvas_headers.dup
unmatched_headers << 'unmatched_login_id'
puts "\nResult summary:"
puts "   Matched staff users for remap: #{remap_data.count}"
writecsv("#{analysisdir}/#{options[:client]}-remapdata", %w[old_id new_id type method match_data canvas_user_id canvas_login_id], remap_data, true, false) unless remap_data.nil?
puts "   Unmatched staff users that cannot be remapped: #{unmatched_data.count}"
writecsv("#{analysisdir}/#{options[:client]}-unmatched_staff_users", unmatched_headers, unmatched_data, true, { 'login_id' => 'previous-login_id', 'unmatched_login_id' => 'login_id' }) unless unmatched_data.nil?
puts "   Users that are not idenifiable staff or students that I have no idea what to do with: #{unknown_data.count}"
writecsv("#{analysisdir}/#{options[:client]}-unknown_users", canvas_headers, unknown_data, true, false) unless unknown_data.nil?
puts "   Kimono users that have duplicate local_ids: #{duplicate_local_id.count}"
writecsv("#{analysisdir}/#{options[:client]}-dup_local_ids", kimono_headers, duplicate_local_id_data, true, false) unless duplicate_local_id_data.nil?
