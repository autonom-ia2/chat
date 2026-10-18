# Lida no WhatsApp do cliente (#1702) fora do request: a abertura da conversa não espera a Meta nem o WAHA.
# Fila low: é cosmético, atrás das respostas (high) e do "digitando" (medium).
# Debounce por conversa: a primeira abertura reserva a conversa por ESPERA e o job roda no fim dela, olhando a última
# recebida daquele momento; as aberturas no meio (trocar de conversa e voltar, rolar, responder) não geram outra chamada.
class ConversaCanal::LeituraNoCanalJob < ApplicationJob
  queue_as :low

  ESPERA = 3.seconds

  def self.agendar(conversation)
    return unless Redis::Alfred.set("conversa_canal:leitura:#{conversation.id}", '1', nx: true, ex: ESPERA.to_i)

    set(wait: ESPERA).perform_later(conversation)
  end

  def perform(conversation)
    ConversaCanal::LeituraNoCanal.new(conversation: conversation).perform
  end
end
