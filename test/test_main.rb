# frozen_string_literal: true

# ─── Coverage (must start before loading main.rb) ─────────────────────────────
unless defined?(Coverage) && Coverage.running?
  require 'coverage'
  Coverage.start
end

# ─── Dependencies ─────────────────────────────────────────────────────────────
require 'rspec'
require 'rspec/core/formatters/base_formatter'
require 'open3'
require 'fileutils'
require 'tmpdir'
require 'stringio'

MAIN_RB      = File.expand_path('../main.rb', __dir__)
PROJECT_ROOT = File.dirname(MAIN_RB)

require MAIN_RB

# ─── Custom Formatter ─────────────────────────────────────────────────────────
class ReadableFormatter < RSpec::Core::Formatters::BaseFormatter
  RSpec::Core::Formatters.register(
    self,
    :example_group_started,
    :example_group_finished,
    :example_passed,
    :example_failed,
    :example_pending,
    :dump_summary
  )

  PASS  = "\e[32;1m[ PASS ]\e[0m"
  FAIL  = "\e[31;1m[ FAIL ]\e[0m"
  ERROR = "\e[31;1m[ERROR ]\e[0m"
  SKIP  = "\e[33;1m[ SKIP ]\e[0m"

  DIVIDER     = "\e[90m#{'─' * 72}\e[0m"
  DIVIDER_FAT = "\e[90m#{'═' * 72}\e[0m"

  def initialize(output)
    super
    @depth    = 0
    @failures = []
    @counts   = { passed: 0, failed: 0, pending: 0 }
  end

  # Top-level describe groups cycle through distinct colors
  GROUP_COLORS = [
    "\e[34;1m",  # bold blue
    "\e[35;1m",  # bold magenta
    "\e[36;1m",  # bold cyan
    "\e[33;1m",  # bold yellow
  ].freeze

  def example_group_started(notification)
    group = notification.group
    if group.parent_groups.size <= 1
      output.puts if @depth.zero?
      color = GROUP_COLORS[@depth % GROUP_COLORS.size]
      output.puts "  #{color}#{group.description}\e[0m"
    else
      output.puts "    #{'  ' * (@depth - 1)}\e[90m▸ \e[0m\e[37m#{group.description}\e[0m"
    end
    @depth += 1
  end

  def example_group_finished(_notification)
    @depth -= 1 if @depth > 0
  end

  def example_passed(notification)
    @counts[:passed] += 1
    print_example(PASS, notification.example)
  end

  def example_failed(notification)
    @counts[:failed] += 1
    ex    = notification.example
    exc   = ex.execution_result.exception
    badge = exc.is_a?(RSpec::Expectations::ExpectationNotMetError) ? FAIL : ERROR
    print_example(badge, ex)
    @failures << notification
  end

  def example_pending(notification)
    @counts[:pending] += 1
    ex = notification.example
    output.puts "    #{'  ' * [0, @depth - 1].max}#{SKIP}  #{ex.description}"
  end

  def dump_summary(notification)
    output.puts
    output.puts DIVIDER_FAT

    unless @failures.empty?
      output.puts "\n  \e[1;31mFailures:\e[0m\n"
      @failures.each_with_index do |n, i|
        ex  = n.example
        exc = ex.execution_result.exception
        output.puts "  \e[1m#{i + 1}) #{ex.full_description}\e[0m"
        exc.message.lines.first(6).each do |line|
          output.puts "     \e[31m#{line.rstrip}\e[0m"
        end
        output.puts "     \e[90m# #{ex.location}\e[0m"
        output.puts
      end
      output.puts DIVIDER
    end

    t   = notification.examples.size
    p   = @counts[:passed]
    f   = @counts[:failed]
    s   = @counts[:pending]
    sec = format('%.3fs', notification.duration)

    parts = ["\e[32m#{p} passed\e[0m"]
    parts << "\e[31m#{f} failed\e[0m"  if f > 0
    parts << "\e[33m#{s} pending\e[0m" if s > 0

    overall = f.zero? ? "\e[32;1m✔  All #{t} tests passed\e[0m" : "\e[31;1m✖  #{f} of #{t} tests failed\e[0m"
    output.puts "\n  #{overall}"
    output.puts "  #{parts.join('  |  ')}  \e[90m(#{sec})\e[0m"
    output.puts DIVIDER_FAT
  end

  private

  def print_example(badge, example)
    indent = '  ' * [0, @depth - 1].max
    time   = format('%.3fs', example.execution_result.run_time)
    output.puts "    #{indent}#{badge}  #{example.description}  \e[90m(#{time})\e[0m"
  end
end

# ─── Helpers ──────────────────────────────────────────────────────────────────

STEP_ENV_KEYS = %w[SDKMAN_DIR AC_SELECTED_JAVA_VERSION AC_ENV_FILE_PATH].freeze

def java_home_keys(env = ENV)
  env.keys.grep(/\AJAVA_HOME_/)
end

# Saves and clears every variable the step reads, runs the block, then restores them.
def with_clean_env
  keys = STEP_ENV_KEYS + java_home_keys
  old  = keys.to_h { |k| [k, ENV[k]] }
  keys.each { |k| ENV.delete(k) }
  yield
ensure
  (STEP_ENV_KEYS + java_home_keys).each { |k| ENV.delete(k) }
  old.each { |k, v| ENV[k] = v unless v.nil? }
end

def fake_status(success)
  double('Process::Status', success?: success)
end

# Stubs Open3.capture3 so no real command runs. Each call records the command
# and returns the next response; the last response is reused once exhausted.
def stub_capture3(*responses, recorder: nil)
  queue = responses.empty? ? [['', '', true]] : responses.dup
  allow(Open3).to receive(:capture3) do |cmd|
    recorder&.<<(cmd)
    stdout, stderr, success = queue.size > 1 ? queue.shift : queue.first
    [stdout, stderr, fake_status(success)]
  end
end

def capture_stdout
  old = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old
end

# Runs the block and returns [stdout, SystemExit or nil].
def capture_exit
  exit_error = nil
  out = capture_stdout do
    yield
  rescue SystemExit => e
    exit_error = e
  end
  [out, exit_error]
end

# Builds a fake SDKMAN install under base with the given Java candidates.
def build_sdkman(base, candidates)
  java_dir = File.join(base, 'candidates', 'java')
  FileUtils.mkdir_p(java_dir)
  candidates.each { |c| FileUtils.mkdir_p(File.join(java_dir, c)) }
  base
end

def current_link(sdkman_dir)
  File.join(sdkman_dir, 'candidates', 'java', 'current')
end

# Ruby's Coverage resets a file's counters on every `load`, so a snapshot is
# taken before each load and summed into the final report.
COVERAGE_SNAPSHOTS = []

def snapshot_coverage
  return unless defined?(Coverage) && Coverage.running?

  data = Coverage.peek_result[MAIN_RB]
  COVERAGE_SNAPSHOTS << data if data
end

# Runs main.rb's step body in-process with the given ENV.
# Returns [stdout, SystemExit or nil].
def run_step(env)
  with_clean_env do
    env.each { |k, v| ENV[k] = v }
    old_program_name = $PROGRAM_NAME
    $PROGRAM_NAME = MAIN_RB
    snapshot_coverage
    begin
      capture_exit { load MAIN_RB }
    ensure
      $PROGRAM_NAME = old_program_name
    end
  end
end

# Runs main.rb in a subprocess with the given ENV. Every variable the step reads
# is unset first (a nil value unsets it in the child), so the ambient
# environment cannot leak in.
def run_main(env = {})
  clean_env = (STEP_ENV_KEYS + java_home_keys).to_h { |k| [k, nil] }
  Open3.capture3(clean_env.merge(env), "ruby #{MAIN_RB}")
end

# Writes a fake `javac` that reports the version of whatever the SDKMAN `current`
# link points to (or default_version when there is no link), the same way the
# real javac on the runner follows the link.
def write_fake_javac(bin_dir, default_version)
  FileUtils.mkdir_p(bin_dir)
  path = File.join(bin_dir, 'javac')
  File.write(path, <<~SH)
    #!/bin/sh
    link="$SDKMAN_DIR/candidates/java/current"
    if [ -L "$link" ]; then
      name=$(basename "$(readlink "$link")")
      echo "javac ${name%%-*}"
    else
      echo "javac #{default_version}"
    fi
  SH
  File.chmod(0o755, path)
  bin_dir
end

# ─── Tests ────────────────────────────────────────────────────────────────────

RSpec.describe '#get_info_msg' do
  it 'prints the message in green on a new line' do
    out = capture_stdout { get_info_msg('Java version: 17.0.9') }
    expect(out).to eq(" \n#{'Java version: 17.0.9'.green}\n")
  end

  it 'prints only the color codes for an empty message' do
    out = capture_stdout { get_info_msg('') }
    expect(out).to eq(" \n#{''.green}\n")
  end

  it 'raises NoMethodError for a nil message' do
    expect { capture_stdout { get_info_msg(nil) } }.to raise_error(NoMethodError)
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#get_env_variable' do
  around do |example|
    old = ENV['_TEST_VAR']
    example.run
    old.nil? ? ENV.delete('_TEST_VAR') : ENV['_TEST_VAR'] = old
  end

  it 'returns the value when the key is set' do
    ENV['_TEST_VAR'] = 'hello'
    expect(get_env_variable('_TEST_VAR')).to eq('hello')
  end

  it 'returns nil when the key is missing' do
    ENV.delete('_TEST_VAR')
    expect(get_env_variable('_TEST_VAR')).to be_nil
  end

  it 'returns nil when the value is an empty string' do
    ENV['_TEST_VAR'] = ''
    expect(get_env_variable('_TEST_VAR')).to be_nil
  end

  it 'keeps whitespace-only values as-is' do
    ENV['_TEST_VAR'] = '  '
    expect(get_env_variable('_TEST_VAR')).to eq('  ')
  end

  it 'raises TypeError for a nil key' do
    expect { get_env_variable(nil) }.to raise_error(TypeError)
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#env_has_key' do
  around do |example|
    old = ENV['_TEST_VAR']
    example.run
    old.nil? ? ENV.delete('_TEST_VAR') : ENV['_TEST_VAR'] = old
  end

  before { allow($stderr).to receive(:write) }

  it 'returns the value when the key is set' do
    ENV['_TEST_VAR'] = '/Users/runner/.sdkman'
    expect(env_has_key('_TEST_VAR')).to eq('/Users/runner/.sdkman')
  end

  it 'aborts with "Input <key> is missing." when the key is missing' do
    ENV.delete('_TEST_VAR')
    expect { env_has_key('_TEST_VAR') }.to raise_error(SystemExit) { |e|
      expect(e.status).to eq(1)
      expect(e.message).to eq('Input _TEST_VAR is missing.')
    }
  end

  it 'aborts when the value is an empty string' do
    ENV['_TEST_VAR'] = ''
    expect { env_has_key('_TEST_VAR') }.to raise_error(SystemExit) { |e|
      expect(e.message).to eq('Input _TEST_VAR is missing.')
    }
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#run_command' do
  let(:commands) { [] }

  it 'passes the command string to Open3.capture3 unchanged' do
    stub_capture3(['ok', '', true], recorder: commands)
    run_command('javac -version')
    expect(commands).to eq(['javac -version'])
  end

  it 'returns stdout when the command succeeds with empty stderr' do
    stub_capture3(["javac 17.0.9\n", '', true])
    expect(run_command('javac -version')).to eq("javac 17.0.9\n")
  end

  it 'returns stderr when the command succeeds but writes to stderr (javac 8 style)' do
    stub_capture3(['', "javac 1.8.0_402\n", true])
    expect(run_command('javac -version')).to eq("javac 1.8.0_402\n")
  end

  it 'returns an empty string when the command succeeds silently' do
    stub_capture3(['', '', true])
    expect(run_command('true')).to eq('')
  end

  it 'raises RuntimeError with stderr when the command fails' do
    stub_capture3(['', 'javac: command not found', false])
    expect { run_command('javac -version') }.to raise_error(RuntimeError, 'javac: command not found')
  end

  it 'raises RuntimeError even when a failing command has empty stderr' do
    stub_capture3(['partial output', '', false])
    expect { run_command('false') }.to raise_error(RuntimeError)
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#run_command_with_log' do
  let(:commands) { [] }

  it 'logs the command and returns its output' do
    stub_capture3(['hello', '', true], recorder: commands)
    result = nil
    out = capture_stdout { result = run_command_with_log('echo hello') }
    expect(result).to eq('hello')
    expect(out).to eq("@@[command] echo hello\nhello\n")
    expect(commands).to eq(['echo hello'])
  end

  it 'does not print an empty output line' do
    stub_capture3(['', '', true])
    out = capture_stdout { run_command_with_log('true') }
    expect(out).to eq("@@[command] true\n")
  end

  it 'logs the error and re-raises when the command fails' do
    stub_capture3(['', 'boom', false])
    out = capture_stdout do
      expect { run_command_with_log('false') }.to raise_error(RuntimeError, 'boom')
    end
    expect(out).to eq("@@[command] false\n@@[error] Command failed:\nboom\n")
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#get_java_version' do
  let(:commands) { [] }

  it 'runs `javac -version`' do
    stub_capture3(["javac 17.0.9\n", '', true], recorder: commands)
    get_java_version
    expect(commands).to eq(['javac -version'])
  end

  it 'returns the major version by default' do
    stub_capture3(["javac 17.0.9\n", '', true])
    expect(get_java_version).to eq('17')
  end

  it 'returns the full version when full_version: true' do
    stub_capture3(["javac 17.0.9\n", '', true])
    expect(get_java_version(full_version: true)).to eq('17.0.9')
  end

  it 'returns only the major version when javac reports no minor/patch' do
    stub_capture3(["javac 21\n", '', true])
    expect(get_java_version).to eq('21')
    expect(get_java_version(full_version: true)).to eq('21')
  end

  it 'reads the javac 8 version from stderr' do
    stub_capture3(['', "javac 1.8.0_402\n", true])
    expect(get_java_version).to eq('1')
    expect(get_java_version(full_version: true)).to eq('1.8.0')
  end

  it 'raises NoMethodError when the output cannot be parsed' do
    stub_capture3(['openjdk something unexpected', '', true])
    expect { get_java_version }.to raise_error(NoMethodError)
  end

  it 'raises NoMethodError when the output is empty' do
    stub_capture3(['', '', true])
    expect { get_java_version }.to raise_error(NoMethodError)
  end

  it 'propagates the error when javac fails' do
    stub_capture3(['', 'javac: command not found', false])
    expect { get_java_version }.to raise_error(RuntimeError, 'javac: command not found')
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#abort_with1' do
  it 'prints the error in red and exits with status 1' do
    out, error = capture_exit { abort_with1('Something went wrong') }
    expect(error).to be_a(SystemExit)
    expect(error.status).to eq(1)
    expect(out).to eq("#{'@@[error] Something went wrong'.red}\n")
  end

  it 'still exits with status 1 for an empty message' do
    out, error = capture_exit { abort_with1('') }
    expect(error.status).to eq(1)
    expect(out).to include('@@[error] ')
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#get_available_java_versions' do
  around { |example| with_clean_env { example.run } }

  it 'returns the versions sorted numerically and comma separated' do
    ENV['JAVA_HOME_17_X64'] = '/jdk/17'
    ENV['JAVA_HOME_8_X64']  = '/jdk/8'
    ENV['JAVA_HOME_21_X64'] = '/jdk/21'
    ENV['JAVA_HOME_11_X64'] = '/jdk/11'
    expect(get_available_java_versions).to eq('8, 11, 17, 21')
  end

  it 'returns an empty string when no JAVA_HOME_<v>_X64 variable is set' do
    expect(get_available_java_versions).to eq('')
  end

  it 'skips variables with an empty value' do
    ENV['JAVA_HOME_17_X64'] = '/jdk/17'
    ENV['JAVA_HOME_11_X64'] = ''
    expect(get_available_java_versions).to eq('17')
  end

  it 'ignores variables that do not match JAVA_HOME_<digits>_X64 exactly' do
    ENV['JAVA_HOME_17_X64']   = '/jdk/17'
    ENV['JAVA_HOME_21_ARM64'] = '/jdk/21'
    ENV['JAVA_HOME_X_X64']    = '/jdk/x'
    ENV['MY_JAVA_HOME_11_X64'] = '/jdk/11'
    ENV['JAVA_HOME_8_X64_OLD'] = '/jdk/8'
    expect(get_available_java_versions).to eq('17')
  ensure
    ENV.delete('MY_JAVA_HOME_11_X64')
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe '#switch_sdkman_java' do
  let(:tmpdir)     { Dir.mktmpdir('sdkman_test') }
  let(:sdkman_dir) { build_sdkman(tmpdir, ['17.0.9-tem', '11.0.21-tem']) }
  let(:java_dir)   { File.join(sdkman_dir, 'candidates', 'java') }
  let(:link)       { current_link(sdkman_dir) }

  after { FileUtils.rm_rf(tmpdir) }

  it 'creates the current link pointing to the candidate' do
    out = capture_stdout { switch_sdkman_java(sdkman_dir, '/Library/Java/17.0.9-tem') }
    expect(File.symlink?(link)).to be(true)
    expect(File.readlink(link)).to eq(File.join(java_dir, '17.0.9-tem'))
    expect(out).to include("@@[command] ln -sfn #{File.join(java_dir, '17.0.9-tem')} #{link}")
  end

  it 'replaces an existing current link' do
    File.symlink(File.join(java_dir, '11.0.21-tem'), link)
    capture_stdout { switch_sdkman_java(sdkman_dir, '/opt/jdk/17.0.9-tem') }
    expect(File.readlink(link)).to eq(File.join(java_dir, '17.0.9-tem'))
  end

  it 'resolves the candidate from the basename of java_home only' do
    capture_stdout { switch_sdkman_java(sdkman_dir, "#{tmpdir}/somewhere/else/11.0.21-tem") }
    expect(File.readlink(link)).to eq(File.join(java_dir, '11.0.21-tem'))
  end

  it 'leaves no temporary link behind' do
    capture_stdout { switch_sdkman_java(sdkman_dir, '/jdk/17.0.9-tem') }
    expect(Dir.children(java_dir)).to contain_exactly('17.0.9-tem', '11.0.21-tem', 'current')
  end

  it 'exits 1 when the candidate is not installed in SDKMAN' do
    out, error = capture_exit { switch_sdkman_java(sdkman_dir, '/jdk/21.0.1-tem') }
    expect(error.status).to eq(1)
    expect(out).to include("Java candidate #{File.join(java_dir, '21.0.1-tem')} is not installed in SDKMAN.")
    expect(File.exist?(link)).to be(false)
  end

  it 'exits 1 when SDKMAN has no java candidates directory' do
    empty_sdkman = File.join(tmpdir, 'empty_sdkman')
    FileUtils.mkdir_p(empty_sdkman)
    out, error = capture_exit { switch_sdkman_java(empty_sdkman, '/jdk/17.0.9-tem') }
    expect(error.status).to eq(1)
    expect(out).to include('is not installed in SDKMAN.')
  end

  it 'exits 1 and removes the temporary link when the rename fails' do
    allow(File).to receive(:rename).and_raise(Errno::EACCES, 'rename')
    out, error = capture_exit { switch_sdkman_java(sdkman_dir, '/jdk/17.0.9-tem') }
    expect(error.status).to eq(1)
    expect(out).to include("Failed to point #{link} to #{File.join(java_dir, '17.0.9-tem')}")
    expect(out).to include('Permission denied')
    expect(Dir.children(java_dir)).to contain_exactly('17.0.9-tem', '11.0.21-tem')
  end

  it 'exits 1 and removes the stale temporary link when the symlink cannot be created' do
    stale = "#{link}.#{Process.pid}.tmp"
    File.symlink('/nonexistent', stale)
    out, error = capture_exit { switch_sdkman_java(sdkman_dir, '/jdk/17.0.9-tem') }
    expect(error.status).to eq(1)
    expect(out).to include('Failed to point')
    expect(File.symlink?(stale)).to be(false)
    expect(File.exist?(link)).to be(false)
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe 'step execution' do
  let(:tmpdir)     { Dir.mktmpdir('step_test') }
  let(:sdkman_dir) { build_sdkman(File.join(tmpdir, 'sdkman'), ['11.0.21-tem', '17.0.9-tem']) }
  let(:env_file)   { File.join(tmpdir, 'env_file') }
  let(:commands)   { [] }
  let(:base_env) do
    {
      'SDKMAN_DIR'               => sdkman_dir,
      'AC_SELECTED_JAVA_VERSION' => '17',
      'AC_ENV_FILE_PATH'         => env_file,
      'JAVA_HOME_11_X64'         => '/jdk/11.0.21-tem',
      'JAVA_HOME_17_X64'         => '/jdk/17.0.9-tem'
    }
  end

  before { allow($stderr).to receive(:write) }
  after  { FileUtils.rm_rf(tmpdir) }

  context 'when the selected version differs from the current one' do
    before { stub_capture3(["javac 11.0.21\n", '', true], ["javac 17.0.9\n", '', true], recorder: commands) }

    it 'points the SDKMAN current link to the selected candidate' do
      _out, error = run_step(base_env)
      expect(error).to be_nil
      expect(File.readlink(current_link(sdkman_dir)))
        .to eq(File.join(sdkman_dir, 'candidates', 'java', '17.0.9-tem'))
    end

    it 'appends JAVA_HOME to AC_ENV_FILE_PATH' do
      File.write(env_file, "EXISTING=1\n")
      run_step(base_env)
      expect(File.read(env_file)).to eq("EXISTING=1\nJAVA_HOME=/jdk/17.0.9-tem\n")
    end

    it 'prints the current, selected and resulting Java versions' do
      out, _error = run_step(base_env)
      expect(out).to include("Current (default) Java version: #{'11'.blue}")
      expect(out).to include("Selected Java version: #{'17'.blue}")
      expect(out).to include("Changing the default Java version from #{'11'.blue} to #{'17'.blue}.")
      expect(out).to include('Java version: 17.0.9'.green)
    end

    it 'only runs `javac -version` as a shell command' do
      run_step(base_env)
      expect(commands).to eq(['javac -version', 'javac -version'])
    end
  end

  context 'when the selected version is already the current one' do
    before { stub_capture3(["javac 17.0.9\n", '', true], recorder: commands) }

    it 'exits 0 without switching or writing JAVA_HOME' do
      out, error = run_step(base_env)
      expect(error).to be_a(SystemExit)
      expect(error.status).to eq(0)
      expect(out).to include('The current Java version is already the same as the selected Java version.')
      expect(File.exist?(current_link(sdkman_dir))).to be(false)
      expect(File.exist?(env_file)).to be(false)
      expect(commands).to eq(['javac -version'])
    end
  end

  context 'when the selected version is not available on the runner' do
    before { stub_capture3(["javac 11.0.21\n", '', true], recorder: commands) }

    it 'exits 1 and lists the available versions' do
      out, error = run_step(base_env.merge('AC_SELECTED_JAVA_VERSION' => '21'))
      expect(error.status).to eq(1)
      expect(out).to include('Java version 21 is not available on the runner. Available Java versions: 11, 17.')
      expect(commands).to be_empty
    end

    it 'treats an empty JAVA_HOME_<v>_X64 as not available' do
      out, error = run_step(base_env.merge('JAVA_HOME_17_X64' => ''))
      expect(error.status).to eq(1)
      expect(out).to include('Java version 17 is not available on the runner. Available Java versions: 11.')
    end
  end

  context 'when the selected candidate is not installed in SDKMAN' do
    before { stub_capture3(["javac 11.0.21\n", '', true]) }

    it 'exits 1 without writing JAVA_HOME' do
      out, error = run_step(base_env.merge('JAVA_HOME_17_X64' => '/jdk/17.0.2-zulu'))
      expect(error.status).to eq(1)
      expect(out).to include('17.0.2-zulu is not installed in SDKMAN.')
      expect(File.exist?(env_file)).to be(false)
    end
  end

  context 'when javac fails' do
    before { stub_capture3(['', 'javac: command not found', false]) }

    it 'raises with the javac error and does not switch' do
      expect { run_step(base_env) }.to raise_error(RuntimeError, 'javac: command not found')
      expect(File.exist?(current_link(sdkman_dir))).to be(false)
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe 'ENV validation (subprocess)' do
  let(:tmpdir)     { Dir.mktmpdir('env_val_test') }
  let(:sdkman_dir) { build_sdkman(File.join(tmpdir, 'sdkman'), ['11.0.21-tem', '17.0.9-tem']) }
  let(:bin_dir)    { write_fake_javac(File.join(tmpdir, 'bin'), '11.0.21') }
  let(:base_env) do
    {
      'PATH'                     => "#{bin_dir}#{File::PATH_SEPARATOR}#{ENV['PATH']}",
      'SDKMAN_DIR'               => sdkman_dir,
      'AC_SELECTED_JAVA_VERSION' => '17',
      'JAVA_HOME_11_X64'         => File.join(tmpdir, 'jdk', '11.0.21-tem'),
      'JAVA_HOME_17_X64'         => File.join(tmpdir, 'jdk', '17.0.9-tem')
    }
  end

  after { FileUtils.rm_rf(tmpdir) }

  shared_examples 'aborts with message' do |env_override, expected_pattern|
    it "exits non-zero and stderr matches /#{expected_pattern.source}/" do
      env = env_override.is_a?(Proc) ? instance_exec(&env_override) : env_override
      _out, err, status = run_main(env)
      expect(status.exitstatus).not_to eq(0)
      expect(err).to match(expected_pattern)
    end
  end

  context 'required variable: SDKMAN_DIR' do
    context 'when missing' do
      include_examples 'aborts with message', {}, /Input SDKMAN_DIR is missing\./
    end

    context 'when an empty string' do
      include_examples 'aborts with message', { 'SDKMAN_DIR' => '' }, /Input SDKMAN_DIR is missing\./
    end
  end

  context 'required variable: AC_SELECTED_JAVA_VERSION' do
    context 'when missing' do
      include_examples 'aborts with message',
                       { 'SDKMAN_DIR' => '/tmp/sdkman' },
                       /Input AC_SELECTED_JAVA_VERSION is missing\./
    end

    context 'when an empty string' do
      include_examples 'aborts with message',
                       { 'SDKMAN_DIR' => '/tmp/sdkman', 'AC_SELECTED_JAVA_VERSION' => '' },
                       /Input AC_SELECTED_JAVA_VERSION is missing\./
    end
  end

  context 'required variable: AC_ENV_FILE_PATH' do
    context 'when missing' do
      include_examples 'aborts with message', -> { base_env }, /no implicit conversion of nil into String/
    end

    context 'when an empty string' do
      include_examples 'aborts with message', -> { base_env.merge('AC_ENV_FILE_PATH' => '') },
                       /No such file or directory/
    end
  end

  context 'selected version not available on the runner' do
    it 'exits 1 and lists the available versions on stdout' do
      out, _err, status = run_main(base_env.merge('AC_SELECTED_JAVA_VERSION' => '21'))
      expect(status.exitstatus).to eq(1)
      expect(out).to include('Java version 21 is not available on the runner. Available Java versions: 11, 17.')
    end
  end

  context 'all variables set' do
    let(:env_file) { File.join(tmpdir, 'env_file') }

    it 'switches Java, writes JAVA_HOME and exits 0' do
      out, err, status = run_main(base_env.merge('AC_ENV_FILE_PATH' => env_file))
      expect(err).to eq('')
      expect(status.exitstatus).to eq(0)
      expect(File.readlink(current_link(sdkman_dir)))
        .to eq(File.join(sdkman_dir, 'candidates', 'java', '17.0.9-tem'))
      expect(File.read(env_file)).to eq("JAVA_HOME=#{base_env['JAVA_HOME_17_X64']}\n")
      expect(out).to include('Java version: 17.0.9')
    end

    it 'exits 0 without writing JAVA_HOME when the version is already selected' do
      out, err, status = run_main(base_env.merge('AC_SELECTED_JAVA_VERSION' => '11',
                                                 'AC_ENV_FILE_PATH'         => env_file))
      expect(err).to eq('')
      expect(status.exitstatus).to eq(0)
      expect(out).to include('The current Java version is already the same as the selected Java version.')
      expect(File.exist?(env_file)).to be(false)
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────

RSpec.describe 'loading main.rb' do
  it 'does not execute the step when required from another script' do
    out, err, status = Open3.capture3({ 'SDKMAN_DIR' => nil, 'AC_SELECTED_JAVA_VERSION' => nil },
                                      "ruby -e 'require %q(#{MAIN_RB}); puts :loaded'")
    expect(status.exitstatus).to eq(0)
    expect(err).to eq('')
    expect(out.strip).to eq('loaded')
  end
end

# ─── Coverage Report ──────────────────────────────────────────────────────────
def print_coverage_report
  return unless defined?(Coverage) && Coverage.running?

  result = begin
    Coverage.result(stop: false, clear: false)
  rescue ArgumentError
    Coverage.result
  end

  main_path = result.keys.find { |p| p&.end_with?('main.rb') }
  return puts("\nCoverage: main.rb not found in results") unless main_path

  data      = COVERAGE_SNAPSHOTS.reduce(result[main_path]) do |acc, snap|
    acc.zip(snap).map { |a, b| a.nil? ? nil : a + b.to_i }
  end
  lines     = data.each_with_index.reject { |c, _| c.nil? }
  total     = lines.size
  covered   = lines.count { |c, _| c.to_i > 0 }
  pct       = total.positive? ? (covered * 100.0 / total).round(1) : 100.0
  uncovered = lines.select { |c, _| c.to_i == 0 }.map { |_, i| i + 1 }

  color = pct == 100 ? "\e[32;1m" : pct >= 80 ? "\e[33m" : "\e[31m"
  bar_filled = (pct / 5).round
  bar = "\e[32m" + '█' * bar_filled + "\e[90m" + '░' * (20 - bar_filled) + "\e[0m"

  puts "\n\e[90m#{'═' * 72}\e[0m"
  puts '  Coverage Report'
  puts "\e[90m#{'─' * 72}\e[0m"
  puts "  main.rb  #{bar}  #{color}#{pct}%\e[0m  (#{covered}/#{total} lines)"
  if uncovered.any? && uncovered.size <= 20
    puts "  Uncovered lines: \e[90m#{uncovered.join(', ')}\e[0m"
  elsif uncovered.any?
    puts "  Uncovered lines: \e[90m#{uncovered.first(15).join(', ')} … (+#{uncovered.size - 15} more)\e[0m"
  end
  puts "\e[90m#{'═' * 72}\e[0m"
end

# ─── Runner ───────────────────────────────────────────────────────────────────
if __FILE__ == $PROGRAM_NAME
  RSpec.configure do |config|
    config.add_formatter ReadableFormatter
    config.color        = true
    config.order        = :defined
  end

  exit_code = RSpec::Core::Runner.run(['--order', 'defined'])
  print_coverage_report
  exit exit_code
end
