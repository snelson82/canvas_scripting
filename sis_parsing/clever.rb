require 'csv'
require 'date'
require 'json'
require 'byebug'
require 'colorize'
require 'terminal-table'

# TODO: Add prompt for the value being used for login_id
# TODO: Add arrays for users with available login_id mapping and those without
# TODO: Add terminal output tables to display counts for those with and without login_id values available

# Parse JSON file and set client name for CSV output file names
op = JSON.parse(File.read(File.expand_path('original.json', 'sis_parsing/raw_json')))
client_name = ''

## ORGS / SCHOOLS
accounts = op['accounts']
accounts_file = File.open(File.expand_path("#{client_name}_schools.json", 'sis_parsing/1r_endpoint_csvs'), 'w')
accounts_file.write(JSON.pretty_generate(accounts))
accounts_file.close

school_ids = []
accounts.each do |school|
  school_ids << school['_original']['sourcedId']
end

## USERS / STUDENTS / TEACHERS
users = op['users']
users_file = File.open(File.expand_path("#{client_name}_users.json", 'sis_parsing/1r_endpoint_csvs'), 'w')
users_file.write(JSON.pretty_generate(users))
users_file.close

admin_users               = []
student_users             = []
faculty_users             = []
enr_start_dates           = []
unknown_role_users        = []
student_login_issues      = []
faculty_login_issues      = []
users_without_enrollments = []

## email_<role> arrays would be used for login_id mapping checks
users.each do |usr|
  case usr['_internal']['role']
  when 'teacher'
    # If the user's role is "teacher", check their login values and add them to the teachers CSV
    faculty_users << usr

    # Update this to include the dependencies used. Should be an array of values from the iterated user, "usr"
    faculty_login_values = [usr['email']]

    users_without_enrollments << { name: "#{usr['first_name']} #{usr['last_name']}", user_id: usr['user_id'], enrollment_sections: [], enrollment_count: 0 } if users_without_enrollments.find { |x| x[:user_id] == usr['user_id'] }.nil?

    usr_issues = {
      user_id: usr['user_id'],
      missing_values: []
    }

    faculty_login_values.each do |login_value|
      usr_issues[:missing_values] << login_value if login_value.nil?
    end

    faculty_login_issues << usr unless usr_issues[:missing_values].empty?
  when 'student'
    # If the user's role is "student", check their login values and add them to the students CSV
    student_users << usr

    # Update this to include the dependencies used. Should be an array of values from the iterated user, "usr"
    student_login_values = [usr['login_id']]

    users_without_enrollments << { name: "#{usr['first_name']} #{usr['last_name']}", user_id: usr['user_id'], enrollment_sections: [], enrollment_count: 0 } if users_without_enrollments.find { |x| x[:user_id] == usr['user_id'] }.nil?

    usr_issues = {
      user_id: usr['user_id'],
      missing_values: []
    }

    student_login_values.each do |login_value|
      usr_issues[:missing_values] << login_value if login_value.nil?
    end

    student_login_issues << usr unless usr_issues[:missing_values].empty?
  when 'schoolAdmin'
    admin_users << usr
  else
    unknown_role_users << usr
  end
end

students_file = File.open(File.expand_path("#{client_name}_students.json", 'sis_parsing/1r_endpoint_csvs'), 'w')
students_file.write(JSON.pretty_generate(student_users))
students_file.close

teachers_file = File.open(File.expand_path("#{client_name}_teachers.json", 'sis_parsing/1r_endpoint_csvs'), 'w')
teachers_file.write(JSON.pretty_generate(faculty_users))
teachers_file.close

admins_file = File.open(File.expand_path("#{client_name}_admins.json", 'sis_parsing/1r_endpoint_csvs'), 'w')
admin_import_file = File.expand_path("#{client_name}_admin_import.csv", 'sis_parsing/1r_endpoint_csvs')
CSV.open(admin_import_file, 'w') { |csv| csv << %w[user_id account_id role status] }
admins_file.write(JSON.pretty_generate(admin_users))
admins_file.close

@f = CSV.open(admin_import_file, 'a+')
admin_users.each do |admin|
  @user_id     = "admin_#{admin['_original']['data']['staff_id']}"
  account_ids = admin['_original']['data']['schools']
  account_ids.each do |subaccount|
    @f << [
      @user_id,
      subaccount,
      'AccountAdmin',
      'active'
    ]
  end
end

@f.close

## CLASSES / SECTIONS
sections = op['sections']
classes_file = File.open(File.expand_path("#{client_name}_classes.json", 'sis_parsing/1r_endpoint_csvs'), 'w')
classes_file.write(JSON.pretty_generate(sections))
classes_file.close

## COURSES
courses = op['courses']
courses_file = File.open(File.expand_path("#{client_name}_courses.json", 'sis_parsing/1r_endpoint_csvs'), 'w')
courses_file.write(JSON.pretty_generate(courses))
courses_file.close

## ENROLLMENTS
enrollments = op['enrollments']
enrollments_file = File.open(File.expand_path("#{client_name}_enrollments.json", 'sis_parsing/1r_endpoint_csvs'), 'w')
enrollments_file.write(JSON.pretty_generate(enrollments))
enrollments_file.close

student_enrollments = []
faculty_enrollments = []

# ENROLLMENTS
enrollments.each do |enr|
  target_section = sections.find { |section| section['section_id'] == enr['section_id'] }
  next unless target_section['_internal'].has_key?('term')

  enrollment_start_date = target_section['_internal']['term']['data']['start_date']
  next unless enr['status'] == 'active' && enrollment_start_date

  # next if enr['_original']['beginDate'].nil? || enr['status'] == 'deleted'
  ## Clever JSON only has user_id, section_id, role, status
  ## It looks like we'll need to get the date from the section data

  target_user = users_without_enrollments.find { |x| x[:user_id] == enr['user_id'] }
  next if target_user.nil?

  target_user[:enrollment_count] += 1

  enr_start_dates     << enrollment_start_date
  student_enrollments << enr if enr['role'] == 'student' && enr['status'] == 'active'
  faculty_enrollments << enr unless enr['role'] == 'student' && enr['status'] == 'active'
end

date_counts = enr_start_dates.each_with_object(Hash.new(0)) do |dt, hsh|
  hsh[dt] += 1
end

updated_date_counts = date_counts.sort_by { |k, _v| [k] }.to_h
users_without_enrollments.sort_by { |usr| usr[:user_id] }

## TERMS
terms = op['terms']
terms_file = File.open(File.expand_path("#{client_name}_terms.json", 'sis_parsing/1r_endpoint_csvs'), 'w')
terms_file.write(JSON.pretty_generate(terms))
terms_file.close

## Terminal output methods

def main_output(student_arr, faculty_arr, course_arr, section_arr, term_arr, account_arr, fac_enr_arr, stu_enr_arr)
  @rows = []
  @rows << ['Accounts', account_arr.length]
  @rows << ['Terms', term_arr.length]
  @rows << ['Courses', course_arr.length]
  @rows << ['Sections', section_arr.length]
  @rows << ['Staff', faculty_arr.length]
  @rows << ['Staff Enrollments', fac_enr_arr.length]
  @rows << ['Students', student_arr.length]
  @rows << ['Student Enrollments', stu_enr_arr.length]

  user_table = Terminal::Table.new(
    title: 'Overview',
    headings: ['Object Type', 'Count'],
    rows: @rows,
    style: {
      border_x: '='.bold.light_blue,
      border_i: 'x'.bold.light_red
    }
  )
  puts "\n"
  puts user_table
end

def enrollment_output(enr_date_rollup)
  @rows = []
  enr_date_rollup.each do |k, v|
    dt = if DateTime.parse(k) > DateTime.now
           k.to_s.bold.light_red
         else
           k
         end
    @rows << [dt, v]
  end

  enrollment_table = Terminal::Table.new(
    title: 'Enrollments Summary',
    headings: ['Start Date', 'Count'],
    rows: @rows,
    style: {
      border_x: '='.bold.light_blue,
      border_i: 'x'.bold.light_red
    }
  )
  puts "\n"
  puts enrollment_table
end

def users_without_enrollment_output(enr_count_arr)
  @rows = []
  enr_count_arr.each do |usr|
    next if usr[:enrollment_count].positive?

    @rows << [usr[:name], usr[:user_id], usr[:enrollment_count]]
  end

  enrollment_count_table = Terminal::Table.new(
    title: 'Users with Enrollment Counts',
    headings: %w[Name user_id Count],
    rows: @rows,
    style: {
      border_x: '='.bold.light_blue,
      border_i: 'x'.bold.light_red
    }
  )
  puts "\n"
  puts enrollment_count_table
end

# Actual script processing

main_output(student_users, faculty_users, courses, sections, terms, accounts, faculty_enrollments, student_enrollments)
enrollment_output(updated_date_counts)
users_without_enrollment_output(users_without_enrollments)
