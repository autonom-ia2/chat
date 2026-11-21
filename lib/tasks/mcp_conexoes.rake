# #3106 — roda logo depois da troca de tráfego do deploy que leva a migration 20261121140000. Pega a conexão OAuth
# que o servidor antigo tenha emitido entre a migration e a troca (ela nasceria com a promessa de uma conta só).
# ATE é o momento da troca (ISO 8601); sem ele, vale agora. Só desativa (revoked_at), nada é apagado.
#
#   bundle exec rails 'mcp:revogar_conexoes_antigas[2026-11-22T03:10:00-03:00]'
namespace :mcp do
  desc 'Desativa as conexões OAuth ativas criadas até ATE (padrão: agora)'
  task :revogar_conexoes_antigas, [:ate] => :environment do |_task, args|
    require Rails.root.join('lib/oauth_conexoes_antigas')

    ate = args[:ate].present? ? Time.zone.iso8601(args[:ate]) : Time.current
    desativadas = OauthConexoesAntigas.revogar!(ate: ate)
    puts "conexões desativadas até #{ate.iso8601}: tokens=#{desativadas[:tokens]} autorizações=#{desativadas[:autorizacoes]}"
  end
end
