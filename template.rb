require "bundler"
require "json"
RAILS_REQUIREMENT = "~> 6.1.0".freeze

def rails_version
  @rails_version ||= Gem::Version.new(Rails::VERSION::STRING)
end

def install_gems
  gem 'bcrypt', '~> 3.1.7'
  gem 'redis', '~> 4.0'
  gem 'sidekiq'
  gem_group :development, :test do
    gem "rspec-rails"
  end
  run 'gem install mailcatcher --no-ri --no-rdoc'
  run 'gem install foreman --no-ri --no-rdoc'
end

def start_spring
  say "Start spring"
  run "spring start"
end

def add_uuid_primary_keys
  say "Enabling uuid primary keys"
  generate "migration", "enable_pg_crypto"
  index_migration_array = Dir['db/migrate/*_enable_pg_crypto.rb']
  index_migration_file = index_migration_array.first
  in_root { insert_into_file index_migration_file, 
    "\n    enable_extension 'pgcrypto'", after: "change" }
  uuid_initializer = <<-CODE
  Rails.application.config.generators do |g|
    g.orm :active_record, primary_key_type: :uuid
  end
CODE
  initializer 'generator.rb', uuid_initializer
end

def add_rspec
  say "Adding rspec"
  generate "rspec:install"
end

def add_sidekiq
  say "Adding sidekiq"
  environment "config.active_job.queue_adapter = :sidekiq"
  environment "config.active_job.queue_name_prefix = \"#{original_app_name}_development\"", env: 'development'
  environment "config.active_job.queue_name_prefix = \"#{original_app_name}_production\"", env: 'production'

  insert_into_file "config/routes.rb",
    "require 'sidekiq/web'\n\n",
    before: "Rails.application.routes.draw do"

  content = <<-CODE
  if Rails.env.development?
    mount Sidekiq::Web => '/sidekiq'
  else
    authenticate :user, lambda { |u| u.admin? } do
      mount Sidekiq::Web => '/sidekiq'
    end
  end
  CODE
  insert_into_file "config/routes.rb", "  #{content}\n", after: "Rails.application.routes.draw do\n"
  
  file 'config/sidekiq.yml', <<~RUBY
  ---
  :concurrency: 2
  :queues:
    - #{original_app_name}_development_default
    - #{original_app_name}_development_mailers
  RUBY
end

def add_smtp
  say "Adding smtp"
  environment "config.action_mailer.raise_delivery_errors = false", env: "development"
  environment "config.action_mailer.perform_caching = false", env: "development"
  environment "config.action_mailer.perform_deliveries = true", env: "development"
  environment "config.action_mailer.delivery_method = :smtp # or :sendmail", env: "development"
  environment "config.action_mailer.smtp_settings = { address: 'localhost', port: 1025 }", env: "development"
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: "development"
  environment "config.action_mailer.asset_host = 'http://localhost:3000' # for assets", env: "development"
end

def add_foreman
  say "Adding foreman"
  file "Procfile.dev", <<~RUBY
  web: bundle exec rails server
  worker: bundle exec sidekiq -C config/sidekip.yml
  mailcatcher: mailcatcher --foreground --http-ip=0.0.0.0
  RUBY
end

def add_tailwind
  say "Adding tailwind CSS"
  run "yarn add -D tailwindcss@npm:@tailwindcss/postcss7-compat @tailwindcss/postcss7-compat postcss@^7 autoprefixer@^9"
  run "npx tailwindcss init"
  insert_into_file "tailwind.config.js", "\n    \"./app/**/*.html.erb\",\n    ", after: "purge: ["
  file "app/javascript/application.css", <<~RUBY
  @import "tailwindcss/base";
  @import "tailwindcss/utilities";
  @import "tailwindcss/components";
  RUBY
  insert_into_file "app/javascript/packs/application.js", "import  \"../application.css\";\n", after: "import \"channels\"\n"
end

def add_gitignore
  file ".gitignore", <<~BASH
  .vendor/
  BASH
end

install_gems

after_bundle do
  add_uuid_primary_keys
  add_sidekiq
  add_smtp
  add_rspec
  add_tailwind
  add_foreman
  add_gitignore
  rails_command("db:setup")
  rails_command("db:migrate")
  git :init
  git add: "."
  git commit: %Q{ -m 'Initial commit' }
  git branch: %Q{ -m master main }
  start_spring
end