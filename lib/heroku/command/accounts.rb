require "fileutils"
require "yaml"

class Heroku::Command::Accounts < Heroku::Command::Base

  def index
    display "No accounts found." if account_names.empty?

    account_names.each do |name|
      display name
    end
  end

  def add
    name = args.shift

    error("Please specify an account name.") unless name
    error("That account already exists.") if account_exists?(name)

    auth = Heroku::Command::Auth.new(nil)
    username, password = auth.ask_for_credentials

    write_account(name,
      :username      => username,
      :password      => password
    )

    if extract_option("--auto") then
      display "Generating new SSH key"
      system %{ ssh-keygen -t rsa -f #{account_ssh_key(name)} -N "" }

      display "Adding entry to ~/.ssh/config"
      File.open(File.expand_path("~/.ssh/config"), "a") do |file|
        file.puts
        file.puts "Host heroku.#{name}"
        file.puts "  HostName heroku.com"
        file.puts "  IdentityFile #{account_ssh_key(name)}"
        file.puts "  IdentitiesOnly yes"
      end

      display "Adding public key to Heroku account: #{username}"
      client = Heroku::Client.new(username, password)
      client.add_key(File.read(File.expand_path(account_ssh_key(name) + ".pub")))
    else
      display ""
      display "Add the following to your ~/.ssh/config"
      display ""
      display "Host heroku.#{name}"
      display "  HostName heroku.com"
      display "  IdentityFile /PATH/TO/PRIVATE/KEY"
      display "  IdentitiesOnly yes"
    end
  end

  def remove
    name = args.shift

    error("Please specify an account name.") unless name
    error("That account does not exist.") unless account_exists?(name)

    FileUtils.rm_f(account_file(name))

    display "Account removed: #{name}"
  end

  def set
    name = args.shift

    error("Please specify an account name.") unless name
    error("That account does not exist.") unless account_exists?(name)

    %x{ git config heroku.account #{name} }

    git_remotes(Dir.pwd).each do |remote, app|
      %x{ git config remote.#{remote}.url git@heroku.#{name}:#{app}.git }
    end
  end

  def default
    name = args.shift

    error("Please specify an account name.") unless name
    error("That account does not exist.") unless account_exists?(name)

    %x{ git config --global heroku.account #{name} }
  end

## account interface #########################################################

  def self.account(name)
    accounts = Heroku::Command::Accounts.new(nil)
    accounts.send(:account, name)
  end

private ######################################################################

  def account(name)
    error("No such account: #{name}") unless account_exists?(name)
    read_account(name)
  end

  def accounts_directory
    @accounts_directory ||= begin
      directory = File.join(home_directory, ".heroku", "accounts")
      FileUtils::mkdir_p(directory)
      directory
    end
  end

  def account_file(name)
    File.join(accounts_directory, name)
  end

  def account_names
    Dir[File.join(accounts_directory, "*")].map { |d| File.basename(d) }
  end

  def account_exists?(name)
    account_names.include?(name)
  end

  def account_ssh_key(name)
    "~/.ssh/identity.heroku.#{name}"
  end

  def read_account(name)
    YAML::load_file(account_file(name))
  end

  def write_account(name, account)
    File.open(account_file(name), "w") { |f| f.puts YAML::dump(account) }
  end

  def error(message)
    puts message
    exit 1
  end

end
