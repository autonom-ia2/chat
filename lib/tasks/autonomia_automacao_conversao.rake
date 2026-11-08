# O relatório de conversão da F9 (#2568, épico #2414). Só leitura: não grava nada.
#   bundle exec rails "autonomia:automacao:conversao:relatorio[17]"
# Em produção não roda (lá é só psql); os números reais saem da leitura agregada do doc F9.
namespace :autonomia do
  namespace :automacao do
    namespace :conversao do
      desc 'Relatório F9: o que cada regra e automação de etapa antiga da conta vira no motor novo'
      task :relatorio, [:conta_id] => :environment do |_task, args|
        relatorio = Autonomia::Automacao::Conversao::Relatorio.new(Account.find(args.fetch(:conta_id)))
        relatorio.linhas.each do |linha|
          estado = linha.convertivel? ? 'converte' : "falta #{linha.fases.join(', ')}"
          puts "#{linha.origem} #{linha.id} (#{linha.ligada ? 'ligada' : 'desligada'}): #{estado}"
          linha.faltas.each { |falta| puts "  - falta #{falta[:chave]} (#{falta[:fase]}): #{falta[:detalhe]}" }
          linha.ressalvas.each { |ressalva| puts "  - ressalva #{ressalva}" }
        end
        puts JSON.pretty_generate(relatorio.resumo)
      end
    end
  end
end
