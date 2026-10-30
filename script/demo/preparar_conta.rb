# Kit de demo (#2140): dados de exemplo na conta do seed e painel em pt-BR.
# Roda por `rails runner`, chamado pelo `bin/demo up`. Recusa qualquer banco que não seja de demo do kit.
abort 'só em development' unless Rails.env.development?
banco = ActiveRecord::Base.connection.current_database
abort "banco fora do kit de demo: #{banco}" unless banco.start_with?('chatwoot_kitdemo_')

john = User.find_by!(email: 'john@acme.inc')
conta = john.accounts.first
Seeders::AccountSeeder.new(account: conta).perform!
conta.update!(locale: 'pt_BR')
john.update!(ui_settings: (john.ui_settings || {}).merge('locale' => 'pt_BR'))

puts "conta #{conta.id} pronta: #{conta.inboxes.count} caixas, #{conta.contacts.count} contatos, " \
     "#{conta.conversations.count} conversas, #{conta.users.count} pessoas"
