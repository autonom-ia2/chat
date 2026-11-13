# #2907 — Quando a perda de acesso de uma caixa do WhatsApp oficial é confirmada, o Guia avisa os administradores pelo
# canal urgente: aviso na conversa do Guia, sino, push e e-mail (`Autonomia::Guide::Entrega`, o mesmo do WhatsApp API
# caído).
#
# Só os caminhos que confirmam a perda chamam `avisar!`: a checagem de saúde (erro de autorização com a caixa já marcada)
# e o aviso `account_update` da Meta. `prompt_reauthorization!` sozinho não avisa: ele também roda na caixa recém-criada
# com webhook falho ou número pendente, que nunca teve acesso para perder.
#
# Um aviso por queda: a marca no Redis é gravada com SET NX (dois jobs ao mesmo tempo não avisam em dobro) e só sai em
# `reauthorized!` (reconexão, ACCOUNT_RECONNECTED ou checagem boa). A chave do aviso leva o instante da marca. Se a entrega
# falha, a marca sai, e o próximo sinal tenta de novo.
#
# `PELA_META`: a caixa foi marcada pelo aviso da Meta. A checagem de saúde boa não apaga essa marcação (depois de um
# ACCOUNT_OFFBOARDED a Graph ainda lê o número enquanto o envio falha); só a reconexão ou o ACCOUNT_RECONNECTED.
module Whatsapp::AccessLoss::GuideAlert
  MARCA = 'whatsapp:access_loss:avisado:%<channel_id>s'.freeze
  PELA_META = 'whatsapp:access_loss:pela_meta:%<channel_id>s'.freeze

  def self.marcar_pela_meta!(channel) = ::Redis::Alfred.set(format(PELA_META, channel_id: channel.id), 1)

  def self.marcado_pela_meta?(channel) = ::Redis::Alfred.get(format(PELA_META, channel_id: channel.id)).present?

  def self.avisar!(channel)
    return unless channel.provider == 'whatsapp_cloud' && channel.inbox.present?

    marca = format(MARCA, channel_id: channel.id)
    marco = Time.current.to_i
    return unless ::Redis::Alfred.set(marca, marco, nx: true)

    begin
      Autonomia::Guide::Entrega.new(channel.account).whatsapp_oficial_sem_acesso!(channel.inbox, Time.zone.at(marco))
    rescue StandardError
      ::Redis::Alfred.delete(marca)
      raise
    end
  rescue StandardError => e
    Rails.logger.error("[WHATSAPP ACCESS] aviso do Guia falhou channel_id=#{channel&.id}: #{e.class}: #{e.message.to_s[0, 200]}")
  end

  # Prepended em `Channel::Whatsapp`: reconectou, a próxima queda avisa de novo.
  def reauthorized!
    super
    ::Redis::Alfred.delete(format(MARCA, channel_id: id))
    ::Redis::Alfred.delete(format(PELA_META, channel_id: id))
  end
end
