# A MENSAGEM DO ROBÔ JÁ SAIU PARA O CANAL? (#1479 F3) É o que o cartão do turno espera antes de sair
# (`EnviarCartoesJob`): o mapa que chega antes do texto, ou sem ele, confunde. -> :saiu, :pendente ou :falhou.
#
# `failed?` vale em todo canal (o envio que falhou grava o status). `sent` NÃO prova nada: é o default da coluna, toda
# outgoing nasce assim (`Message` enum status, db/schema.rb `messages.status default 0`). Por isso o sinal de "saiu" é o
# que cada envio grava de volta, por tipo de caixa:
#   - WhatsApp Cloud e 360 (`Channel::Whatsapp`): o `source_id` que a Meta devolve, gravado DEPOIS da resposta
#     (`Whatsapp::SendOnWhatsappService#send_session_message`/`send_template_message`: `message.update!(source_id:)`).
#   - Híbrido pelo WhatsApp API (marca `whatsapp_transport = 'web'`, gravada por `WhatsappHybrid::WebTransport#mark_pending!`):
#     ali o `source_id` é o id físico gravado ANTES do envio, e não prova nada. Saiu quando o motor aceitou
#     (`whatsapp_transport_outcome = 'accepted'`, `WebTransport#send_now`, gravado depois do pedido), quando o eco da Meta
#     reconciliou (`whatsapp_web_id`, `WhatsappHybrid::EchoReconcilerExtension`) ou quando o ack chegou (delivered, read).
#     `pending` (plano B do 131047) e `throttled` ainda não são resultado; `uncertain` grava `failed` junto.
#     A mensagem do Híbrido que vai pela Cloud (janela aberta) não leva a marca e segue a regra da Cloud.
#   - WAHA (`Channel::Api` com `provider = 'waha'`): quem envia é o conector, pelo webhook `message_created` da caixa; o
#     `SendReplyJob` só manda a notificação de e-mail. A volta é o PATCH `messages#update` com o status (delivered, read,
#     failed); o conector não grava `source_id` nem um "aceito". Sem sinal positivo confiável: saiu com o ack, ou depois
#     de ESPERA_SEM_SINAL (o conector manda na ordem dos webhooks, e a espera cobre a fila dele). Risco conhecido: se o
#     conector marcar `failed` DEPOIS da espera, o mapa pode já ter saído sem o texto.
#   - Sem envio externo (chat do site, `Channel::Api` comum): a mensagem está na conversa ao gravar, e a ordem é a de
#     criação. Saiu logo.
#   - Os outros canais com envio externo (e-mail, Instagram, Facebook, Telegram, SMS...): o `source_id` que o serviço de
#     envio grava depois do provedor; sem ele, depois de ESPERA_SEM_SINAL (nem todo serviço grava, e o cartão ali sai
#     em texto). O mesmo risco: a falha marcada depois da espera não segura o cartão.
module Autonomia::Agents::Operate::SaidaDaMensagem
  ESPERA_SEM_SINAL = 10.seconds
  PELO_CELULAR = 'web'.freeze
  ACEITO = 'accepted'.freeze

  module_function

  def estado(message)
    return :falhou if message.failed?

    saiu?(message) ? :saiu : :pendente
  end

  def saiu?(message)
    case message.inbox.channel_type
    when 'Channel::Whatsapp' then whatsapp_saiu?(message)
    when 'Channel::Api' then message.inbox.channel.waha_provider? ? ack_ou_espera?(message) : true
    when 'Channel::WebWidget' then true
    else message.source_id.present? || espera_passou?(message)
    end
  end

  def whatsapp_saiu?(message)
    atributos = message.content_attributes.to_h
    return message.source_id.present? unless atributos['whatsapp_transport'] == PELO_CELULAR

    atributos[::WhatsappHybrid::WebTransport::OUTCOME_KEY] == ACEITO || atributos['whatsapp_web_id'].present? ||
      message.delivered? || message.read?
  end

  def ack_ou_espera?(message)
    message.delivered? || message.read? || espera_passou?(message)
  end

  def espera_passou?(message)
    message.created_at <= ESPERA_SEM_SINAL.ago
  end
end
