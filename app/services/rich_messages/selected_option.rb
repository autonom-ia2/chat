# Prepend em Whatsapp::IncomingMessageBaseService (chat#1473, P3): quando o cliente toca num botão de resposta, numa
# opção de lista ou num botão de resposta rápida de modelo, a mensagem recebida guarda, além do título (que o
# Chatwoot já põe em `content`), a opção tocada em `content_attributes.selected_option`:
#   { "id": "agendar", "title": "Agendar visita" }   (sem título quando a Meta não manda um)
# Vale para qualquer botão ou lista (`options`, o `input_select` antigo e os modelos). O robô a recebe no webhook
# (`content_attributes` vai inteiro) e o agente a lê na mensagem. A mensagem que ofereceu as opções continua em
# `in_reply_to`, que o Chatwoot já grava a partir de `context.id`.
# Só acrescenta a chave ao que o Chatwoot monta: não muda conteúdo, conversa nem quem responde.
module RichMessages::SelectedOption
  REPLIES = %i[button_reply list_reply].freeze

  # A opção tocada no item `messages[]` do webhook da Meta, ou nil quando a mensagem não é resposta a botão ou lista.
  def self.from(message)
    reply = REPLIES.lazy.filter_map { |kind| message.dig(:interactive, kind) }.first
    return option(reply[:id], reply[:title]) if reply

    button = message[:button]
    option(button[:payload], button[:text]) if button
  end

  # Sem título (ou com título vazio) grava só o `id`: quem lê procura o título na opção oferecida com esse `id`.
  def self.option(id, title)
    { id: id, title: title.presence }.compact if id.present?
  end

  private

  def message_content_attributes(message)
    selected = RichMessages::SelectedOption.from(message)
    selected ? super.merge(selected_option: selected) : super
  end
end
