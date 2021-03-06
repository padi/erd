require 'rails/generators'

module Erd
  class MigrationError < StandardError; end

  class Migrator
    class << self
      def status
        migrated_versions = ActiveRecord::Base.connection.select_values("SELECT version FROM #{ActiveRecord::Migrator.schema_migrations_table_name}").map {|v| '%.3d' % v}
        migrations = []
        ActiveRecord::Migrator.migrations_paths.each do |path|
          Dir.foreach(Rails.root.join(path)) do |file|
            if (version_and_name = /^(\d{3,})_(.+)\.rb$/.match(file))
              status = migrated_versions.delete(version_and_name[1]) ? 'up' : 'down'
              migrations << {:status => status, :version => version_and_name[1], :name => version_and_name[2], :filename => file}
            end
          end
        end
        migrations += migrated_versions.map {|v| {:status => 'up', :version => v, :name => '*** NO FILE ***', :filename => v}}
        migrations.sort_by {|m| m[:version]}
      end

      # `rake db:migrate`
      # example:
      #   run_migrations up: '/Users/a_matsuda/my_app/db/migrate/20120423023323_create_products.rb'
      #   run_migrations up: '20120512020202', down: ...
      #   run_migrations up: ['20120512020202', '20120609010203', ...]
      def run_migrations(migrations)
        migrations.each do |direction, version_or_filenames|
          Array.wrap(version_or_filenames).each do |version_or_filename|
            /^(?<version>\d{3,})/ =~ File.basename(version_or_filename)
            ActiveRecord::Migrator.run(direction, ActiveRecord::Migrator.migrations_path, version.to_i)
          end if version_or_filenames
        end
        if ActiveRecord::Base.schema_format == :ruby
          File.open(ENV['SCHEMA'] || "#{Rails.root}/db/schema.rb", 'w') do |file|
            ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, file)
          end
        end
        #TODO unload migraion classes
      end

      # runs `rails g model [name]`
      # @return generated migration filename
      def execute_generate_model(name, options = nil)
        result = execute_generator 'model', name, options
        result.flatten.grep(%r(/db/migrate/.*\.rb))
      end

      # runs `rails g migration [name]`
      # @return generated migration filename
      def execute_generate_migration(name, options = nil)
        result = execute_generator 'migration', name, options
        result.last.last
      end

      private
      # a dirty workaround to make rspec-rails run
      def overwriting_argv(value, &block)
        original_argv = ARGV
        Object.const_set :ARGV, value
        block.call
      ensure
        Object.const_set :ARGV, original_argv
      end

      def execute_generator(type, name, options = nil)
        overwriting_argv([name, options]) do
          Rails::Generators.configure! Rails.application.config.generators
          result = Rails::Generators.invoke type, [name, options], :behavior => :invoke, :destination_root => Rails.root
          raise ::Erd::MigrationError, "#{name}#{"(#{options})" if options}" unless result
          result
        end
      end
    end
  end
end
