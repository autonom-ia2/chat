namespace :prospecting do
  # Comparação da nota legada com a do Orth nas buscas de uma conta (#681). Só leitura: roda em produção sem gravar nada.
  # Uso: bundle exec rake 'prospecting:score_shadow_report[ACCOUNT_ID,DIAS]'
  desc 'Compare legacy and Orth prospecting scores for an account (read only)'
  task :score_shadow_report, [:account_id, :days] => :environment do |_task, args|
    account = Account.find(args[:account_id])
    days = (args[:days].presence || 7).to_i
    report = Autonomia::Prospecting::Scoring::ShadowReport.new(account: account, since: days.days.ago).perform

    puts "Conta #{account.id}, últimos #{days} dias"
    puts "Buscas comparadas: #{report[:buscas]} (sem nota sombra: #{report[:buscas_sem_sombra]})"
    puts "Leads: #{report[:leads]}. Sobem: #{report[:sobem]}. Descem: #{report[:descem]}. Iguais: #{report[:iguais]}."
    puts 'Maiores mudanças de prioridade:' if report[:top10].any?
    report[:top10].each.with_index(1) do |row, index|
      puts "#{index}. #{row[:nome]} (lead #{row[:lead_id]}): prioridade #{row[:legacy]} -> #{row[:orth]}, " \
           "#{row[:faixa_legacy]} -> #{row[:faixa_orth]}. #{row[:motivo]}"
    end
  end
end
