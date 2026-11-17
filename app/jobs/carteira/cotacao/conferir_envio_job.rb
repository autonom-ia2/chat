# MINUTOS_PARA_INCERTA depois da reserva do envio da proposta (E8, #2901, Carteira::Cotacao::Proposta): o passo do
# envio ainda sem o id da mensagem quer dizer que o processo caiu entre a reserva e o envio, ou que a mensagem pode ter
# saído sem o id gravado. O passo vira incerto e a equipe é avisada para conferir na conversa, uma vez só
# (Carteira::Cotacao::Proposta.conferir_envio). Passo que saiu, que já está incerto ou que sumiu: nada a fazer.
class Carteira::Cotacao::ConferirEnvioJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  def perform(passo_id)
    passo = Carteira::ApoliceEvento.find_by(id: passo_id)
    Carteira::Cotacao::Proposta.conferir_envio(passo) if passo
  end
end
