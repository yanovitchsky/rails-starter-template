generate(:migration, "enable_pg_crypto")
rails_version = `bundle exec rails -v`.split(' ').last.split('.')[0..1].join('.')
f = Dir['.'][0]
code = <<-CODE
class EnablePgcrypto < ActiveRecord::Migration[#{rails_version}]
  def change
    enable_extension 'pgcrypto'
  end
end
CODE
file f, code

