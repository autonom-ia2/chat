# Kit de demo (#2140): liga uma feature flag numa conta do banco de demo.
# Roda por `rails runner`, chamado pelo `bin/demo flag`. Flag desconhecida falha (não existe `feature_<nome>=`).
abort 'só em development' unless Rails.env.development?
banco = ActiveRecord::Base.connection.current_database
abort "banco fora do kit de demo: #{banco}" unless banco.start_with?('chatwoot_kitdemo_')

flag = ENV.fetch('DEMO_FLAG')
conta = Account.find(ENV.fetch('DEMO_CONTA'))
abort "flag desconhecida: #{flag}" unless conta.respond_to?("feature_#{flag}=")

conta.enable_features!(flag)
puts "flag #{flag} na conta #{conta.id}: #{conta.reload.feature_enabled?(flag) ? 'ligada' : 'NÃO ligou'}"
