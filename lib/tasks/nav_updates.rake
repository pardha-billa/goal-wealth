namespace :nav_updates do
  desc "Update mutual fund and ETF NAV data"
  task update_today_nav: :environment do
    result = NavUpdates::UpdateTodayNav.call
    puts "NAV update finished: #{result.inspect}"
  end
end
