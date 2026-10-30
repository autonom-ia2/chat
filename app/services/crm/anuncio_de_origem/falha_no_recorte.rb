# A falha do recorte do tempo real (#2271) como ela vai ao ChatwootExceptionTracker: a classe e o stack da exceção
# original, com uma mensagem fixa. A mensagem original fica de fora porque pode trazer o SQL da consulta, com os
# pubsub_token de quem recebe o evento (com eles, alguém escuta o tempo real da pessoa).
#
#   Crm::AnuncioDeOrigem::FalhaNoRecorte.de(erro) -> a exceção para o rastreador
class Crm::AnuncioDeOrigem::FalhaNoRecorte < StandardError
  def self.de(erro)
    new("#{erro.class.name} no recorte por destinatário").tap { |falha| falha.set_backtrace(erro.backtrace) }
  end
end
