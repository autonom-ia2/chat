namespace :prospecting do
  # Comparação da nota legada com a do Orth nas buscas de uma conta (#681). Só leitura: roda em produção sem gravar nada.
  # Uso: bundle exec rake 'prospecting:score_shadow_report[ACCOUNT_ID,DIAS]'
  desc 'Compare legacy and Orth prospecting scores for an account (read only)'
  task :score_shadow_report, [:account_id, :days] => :environment do |_task, args|
    account = Account.find(args[:account_id])
    days = (args[:days].presence || 7).to_i
    report = Autonomia::Prospecting::Scoring::ShadowReport.new(account: account, since: days.days.ago).perform
    band = Autonomia::Prospecting::Scoring::Band
    labels = band::CODES.map { |code| band.label(code) }
    width = labels.map(&:size).max + 2

    puts "Conta #{account.id}, últimos #{days} dias"
    puts "Buscas comparadas: #{report[:buscas]} (sem nota sombra: #{report[:buscas_sem_sombra]})"
    puts "Leads: #{report[:leads]}. Sobem de faixa: #{report[:sobem]}. Descem de faixa: #{report[:descem]}. " \
         "Mesma faixa: #{report[:mesma_faixa]}."
    puts 'Faixa legada (linha) -> faixa do Orth (coluna):'
    puts "#{' ' * width}#{labels.map { |label| label.ljust(width) }.join}".rstrip
    band::CODES.each_with_index do |from, index|
      puts "#{labels[index].ljust(width)}#{band::CODES.map { |to| report[:matriz][from][to].to_s.ljust(width) }.join}".rstrip
    end
    puts 'Maiores mudanças de prioridade:' if report[:top10].any?
    report[:top10].each.with_index(1) do |row, index|
      puts "#{index}. #{row[:nome]} (lead #{row[:lead_id]}): prioridade #{row[:legacy]} -> #{row[:orth]}, " \
           "#{row[:faixa_legacy]} -> #{row[:faixa_orth]}. #{row[:motivo]}"
    end
  end
end
