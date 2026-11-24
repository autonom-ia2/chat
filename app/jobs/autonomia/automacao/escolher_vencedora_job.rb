# #3099: escolhe a versão que fica nos passos "mensagem" com duas versões da Automação livre
# (Autonomia::Automacao::DuasVersoes::Teste#decidir!). Cron em config/schedule.yml, a cada 15 minutos. Só olha os
# testes sem vencedora; o passo que saiu da receita (ou deixou de testar duas versões) fica parado, sem escolha. Um teste
# com problema vai ao log e não segura os outros.
class Autonomia::Automacao::EscolherVencedoraJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ::Autonomia::Automacao::VersaoVencedora.testando.includes(automacao: :versao_ativa).find_each do |linha|
      passo = ::Autonomia::Automacao::DuasVersoes.passo_ativo(linha.automacao, linha.passo)
      ::Autonomia::Automacao::DuasVersoes::Teste.new(linha, passo).decidir! if passo
    rescue StandardError => e
      Rails.logger.error "[Autonomia::Automacao::EscolherVencedoraJob] teste=#{linha.id} #{e.class}: #{e.message.truncate(200)}"
    end
  end
end
