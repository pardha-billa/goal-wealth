require 'logger'
require_relative 'boot'
require 'rails/all'

Bundler.require(*Rails.groups)

module GoalwealthRails
  class Application < Rails::Application
    config.load_defaults 6.1
    config.time_zone = 'Asia/Kolkata'
    config.active_record.default_timezone = :local
    config.generators.system_tests = nil
  end
end
