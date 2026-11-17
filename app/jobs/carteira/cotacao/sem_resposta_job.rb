# DIAS_SEM_RESPOSTA depois do "Algo mudou?" (E8, #2901): o segurado não tocou em nenhum botão, e a cotação segue com o
# que está na apólice (Carteira::Cotacao::Cotar). Respondeu antes, nada a fazer: o "Nada mudou" já pediu a cotação e o
# "Mudou algo" a parou. Rodar de novo é seguro: a cotação confere sob a trava se já foi pedida.
class Carteira::Cotacao::SemRespostaJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  def perform(apolice_id, vigencia)
    apolice, config = Carteira::Cotacao.da_vigencia(apolice_id, vigencia)
    return if apolice.nil? || Carteira::Cotacao.passo(apolice, 'respondeu_algo_mudou')

    Carteira::Cotacao::Cotar.new(apolice, config).call
  end
end
