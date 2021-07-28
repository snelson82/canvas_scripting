require 'date'
require 'json'
require 'byebug'
require 'colorize'
require 'terminal-table'

op = JSON.parse(File.read(File.expand_path('original.json', 'sis_parsing/raw_json')))
client_name = ''

## ORGS / SCHOOLS
accounts = op['accounts']
accounts_file = File.open(File.expand_path("#{client_name}_schools.json", 'sis_parsing/exports'), 'w')
accounts_file.write(JSON.pretty_generate(accounts))
accounts_file.close

school_ids = []
accounts.each do |school|
  school_ids << school['_original']['sourcedId']
end

## USERS / STUDENTS / TEACHERS
users = op['users']
users_file = File.open(File.expand_path("#{client_name}_users.json", 'sis_parsing/exports'), 'w')
users_file.write(JSON.pretty_generate(users))
users_file.close

student_users   = []
faculty_users   = []
email_students  = []
email_faculty   = []
enr_start_dates = []

users.each do |usr|
  student_users  << usr if usr['status'] == 'active' && usr['_internal']['staff'] == false
  faculty_users  << usr if usr['status'] == 'active' && usr['_internal']['staff'] == true
  # Students have an ['email'] and ['_original']['SchoolEmail'] value
  email_students << usr if usr['email'] && usr['_internal']['staff'] == false
  # Staff have an ['email'] and ['_original']['Email'] value
  email_faculty  << usr if usr['email'] && usr['_internal']['staff'] == true
end

students_file = File.open(File.expand_path("#{client_name}_students.json", 'sis_parsing/exports'), 'w')
students_file.write(JSON.pretty_generate(student_users))
students_file.close

teachers_file = File.open(File.expand_path("#{client_name}_teachers.json", 'sis_parsing/exports'), 'w')
teachers_file.write(JSON.pretty_generate(faculty_users))
teachers_file.close

## CLASSES
sections = op['sections']
classes_file = File.open(File.expand_path("#{client_name}_classes.json", 'sis_parsing/exports'), 'w')
classes_file.write(JSON.pretty_generate(sections))
classes_file.close

## COURSES
courses = op['courses']
courses_file = File.open(File.expand_path("#{client_name}_courses.json", 'sis_parsing/exports'), 'w')
courses_file.write(JSON.pretty_generate(courses))
courses_file.close

## ENROLLMENTS
enrollments = op['enrollments']
enrollments_file = File.open(File.expand_path("#{client_name}_enrollments.json", 'sis_parsing/exports'), 'w')
enrollments_file.write(JSON.pretty_generate(enrollments))
enrollments_file.close

student_enrollments = []
faculty_enrollments = []

enrollments.each do |enr|
  next if enr['status'] == 'deleted'

  enr_start_dates     << enr['start_date']
  student_enrollments << enr if enr['role'] == 'student'
  faculty_enrollments << enr if enr['role'] == 'teacher'
end

date_counts = enr_start_dates.each_with_object(Hash.new(0)) do |dt, hsh|
  hsh[dt] += 1
end
date_counts.tap { |hsh| hsh.delete(nil) }
updated_date_counts = date_counts.sort_by { |k, _v| [k] }.to_h

## TERMS
terms = op['terms']
terms_file = File.open(File.expand_path("#{client_name}_terms.json", 'sis_parsing/exports'), 'w')
terms_file.write(JSON.pretty_generate(terms))
terms_file.close

## ACADEMIC SESSIONS

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

main_output(student_users, faculty_users, courses, sections, terms, accounts, faculty_enrollments, student_enrollments)
enrollment_output(updated_date_counts)
