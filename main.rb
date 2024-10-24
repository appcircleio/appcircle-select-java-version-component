require 'open3'

def get_env_variable(key)
    return (ENV[key] == nil || ENV[key] == "") ? nil : ENV[key]
end
 
def env_has_key(key)
    value = get_env_variable(key)
    return value unless value.nil? || value.empty?

    abort("Input #{key} is missing.")
end

def run_command(command)
  puts "@@[command] Executing: #{command}"
  stdout_str, stderr_str, status = Open3.capture3(command)

  if status.success?
      return stderr_str.empty? ? stdout_str : stderr_str
  else
      puts "@@[error] Command failed:\n#{stderr_str}"
      raise stderr_str
  end
end

def abort_with0(message)
  puts "@@[error] #{message}"
  exit 0
end

def abort_with1(message)
    puts "@@[error] #{message}"
    exit 1
end

ac_selected_java_version = env_has_key('AC_SELECTED_JAVA_VERSION')
puts "Selected Java version: #{ac_selected_java_version}"

selected_java_version = get_env_variable("JAVA_HOME_#{ac_selected_java_version}_X64")
if !selected_java_version
  abort_with1("Java version #{selected_java_version} is not available on the runner.")
end

current_java_version = run_command('javac -version').match(/javac (\d+)\.\d+\.\d+/)[1]
puts "Current Java Version: #{current_java_version}"

if ac_selected_java_version == current_java_version
    abort_with0("Current Java version is already the same as the selected Java version, #{selected_java_version}.")
end

puts "Changing default Java version #{current_java_version} to selected #{ac_selected_java_version}."
open(ENV['AC_ENV_FILE_PATH'], 'a') { |f|
    f.puts "JAVA_HOME=#{selected_java_version}"
}

puts "New Java version: #{ac_selected_java_version}."