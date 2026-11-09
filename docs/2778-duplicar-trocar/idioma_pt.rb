abort 'seed só roda no banco da demo' unless ActiveRecord::Base.connection.current_database.start_with?('chatwoot_kitdemo_')
Account.find(1).update!(locale: 'pt_BR')
Account.find(1).users.find_each { |u| u.update!(ui_settings: u.ui_settings.to_h.merge('locale' => 'pt_BR')) }
puts 'idioma pt_BR'
