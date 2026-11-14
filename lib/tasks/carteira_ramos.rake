# Bateria de avaliação do "ramo → tipo" da carteira de seguros (E4, #2897): pergunta ao modelo de verdade os ramos de
# lib/tasks/carteira_ramos_casos.json e mostra o acerto por tipo, a matriz de confusão, os erros e o custo estimado.
#
#   CARTEIRA_RAMOS_AVALIAR=sim bundle exec rake carteira:ramos:avaliar
#
# FORA DA CI e DESLIGADA por padrão, de propósito: é chamada paga. Sem `CARTEIRA_RAMOS_AVALIAR=sim` a tarefa não chama
# nada. Com os 140 casos do arquivo são 4 chamadas ao modelo (40 ramos por chamada), que é também o teto padrão;
# `CARTEIRA_RAMOS_TETO=n` muda o teto e `CARTEIRA_RAMOS_CASOS=caminho` troca o arquivo de casos. Passando do teto, a
# tarefa para antes da primeira chamada.
#
# Os casos versionados são só ramos de seguro, como o mercado brasileiro escreve. Nunca ponha aqui nome de cliente, de
# corretora, documento nem número de apólice.
namespace :carteira do
  namespace :ramos do
    desc 'Mede o modelo no ramo → tipo da carteira de seguros (chamada paga; só com CARTEIRA_RAMOS_AVALIAR=sim)'
    task avaliar: :environment do
      abort('Chamada paga: rode com CARTEIRA_RAMOS_AVALIAR=sim. Nada foi chamado.') unless ENV['CARTEIRA_RAMOS_AVALIAR'] == 'sim'
      abort('O modelo não está configurado nesta instalação (TypesafeAi::Config). Nada foi chamado.') unless TypesafeAi::Config.configured?

      classe = Carteira::Trazer::AvaliacaoDosRamos
      casos = classe.casos(ENV.fetch('CARTEIRA_RAMOS_CASOS', classe::CASOS))
      avaliacao = classe.new(casos, pergunta: Carteira::Trazer::PerguntaDoRamo.new(ligado: true), teto: Integer(ENV.fetch('CARTEIRA_RAMOS_TETO', 4)))
      puts "#{casos.size} casos, #{avaliacao.chamadas} chamadas ao modelo #{TypesafeAi::Config.model}."
      resultado = avaliacao.call

      puts "Acerto geral: #{resultado.acertos} de #{resultado.total}"
      puts 'Acerto por tipo:'
      resultado.por_tipo.each { |tipo, (acertos, do_tipo)| puts "  #{tipo.ljust(12)} #{acertos} de #{do_tipo}" }
      puts 'Matriz de confusão (esperado → respondido: quantos):'
      resultado.matriz.sort.each { |(esperado, veio), quantos| puts "  #{esperado.ljust(12)} → #{veio.ljust(12)} #{quantos}" }
      puts 'Erros (ramo: esperado → respondido):'
      resultado.erros.each { |ramo, esperado, veio| puts "  #{ramo}: #{esperado} → #{veio}" }
      uso = resultado.uso
      puts "Consumo: #{uso[:chamadas]} chamadas, #{uso[:input_tokens]} tokens de entrada, #{uso[:output_tokens]} de saída."
      puts format('Custo estimado: US$ %<custo>.6f', custo: resultado.custo)
    rescue Carteira::Trazer::AvaliacaoDosRamos::TetoDeChamadas => e
      abort("Parei antes de chamar o modelo: #{e.message}. Aumente CARTEIRA_RAMOS_TETO se for isso mesmo.")
    end
  end
end
