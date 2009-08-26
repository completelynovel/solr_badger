require 'yaml'

namespace :use_solr_with_uquery do

  desc "Create solr configuration file."
  task :install do
    create_config_file
    create_config_loader
  end

  def create_config_file
    solr_config_path = Rails.root + '/config/solr_config.yml'
    unless File.exists?(solr_config_path)
      config_yml = Hash.new
      config_yml['solr'] = {
        'url' => 'http://localhost:8983/solr/select/',
        'server_url' => 'http://localhost:8983/solr/select/'
      }

      File.open(solr_config_path, 'w') do |out|
        YAML.dump(config_yml, out)
      end

      puts "config/solr_config.yml file created."
      puts "Please fill the file according to your configuration."
    else
      puts "config/solr_config.yml already exists. Aborting task."
    end
  end

  def create_config_loader
    f = File.new(Rails.root + '/config/initializers/solr_config.rb',  'w+')
    f.puts 'SOLR_CONFIG = YAML.load_file("#{RAILS_ROOT}/config/solr_config.yml")'
    f.close

    puts "config/initializers/solr_config.rb file created."
  end
end
