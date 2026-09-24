namespace :nav_updates do
  desc "Update mutual fund and ETF NAV data"
  task update_today_nav: :environment do
    result = NavUpdates::UpdateTodayNav.call
    puts "NAV update finished: #{result.inspect}"

    # Make GitHub Actions go red (and email you) when nothing was updated.
    abort "NAV update failed: no assets updated" if result[:updated].zero?
  end
end
