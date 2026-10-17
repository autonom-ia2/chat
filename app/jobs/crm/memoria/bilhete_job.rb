# Memória das IAs (#1601, W7): a IA melhora o bilhete da passagem (uma chamada, com reserva; ver Crm::Memoria::Bilhete).
# Falhou: o bilhete do código fica e, se ainda há tentativa, tenta de novo em 1 minuto.
class Crm::Memoria::BilheteJob < ApplicationJob
  queue_as :low
  ESPERA = 1.minute

  def perform(passagem_id)
    passagem = Crm::Passagem.find_by(id: passagem_id)
    return if passagem.nil? || !Crm::Memoria.ativa?(passagem.conversation)
    return unless Crm::Memoria::Bilhete.configurado?(passagem)
    return unless Crm::Memoria::Bilhete.reservar!(passagem)

    Crm::Memoria::Bilhete.melhorar!(passagem.reload)
  # Qualquer falha (rede, tempo, resposta fora do formato) devolve o bilhete ao do código e tenta de novo, se der.
  rescue StandardError => e
    Rails.logger.warn("[crm][memoria][bilhete] falhou passagem=#{passagem_id} erro=#{e.class}")
    Crm::Memoria::Bilhete.falhou!(passagem)
    self.class.set(wait: ESPERA).perform_later(passagem_id) if Crm::Memoria::Bilhete.pode_tentar_de_novo?(passagem)
  end
end
