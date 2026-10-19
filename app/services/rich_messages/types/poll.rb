# Enquete (chat#1709): a pergunta e as opções para o cliente votar.
#   { "type": "poll", "options": [{ "id": "sim", "title": "Sim" }, { "id": "nao", "title": "Não" }], "multiple": false }
# O corpo (`content`) é a pergunta. `multiple` (opcional, booleano): o cliente pode marcar mais de uma opção.
# Só existe com a flag `whatsapp_rich_native` na conta (Waha::RichNative::PollGate; sem ela, o tipo é desconhecido,
# como na main). Nativa só pelo motor WAHA (plano B do Híbrido e caixa WAHA comum com o conector customizado); a Meta
# não tem enquete na Cloud API, então lá sai como texto numerado (`whatsapp_cloud_payload`) e a bolha mostra
# "Enviado como texto".
# Limites do motor (sendPoll): pergunta de 1 a 255 caracteres; de 2 a 12 opções, cada título com até 100 caracteres.
# O voto volta pelo TÍTULO da opção (o motor não devolve id): títulos repetidos (depois do strip) são recusados.
# O `id` não vai ao WhatsApp: é o que o robô lê em `selected_option` quando o voto volta. Sem "|", como na lista.
class RichMessages::Types::Poll
  BODY_MAX = 255
  OPTIONS_MIN = 2
  OPTIONS_MAX = 12
  TITLE_MAX = 100
  ID_MAX = 200
  ID_FORBIDDEN = '|'.freeze
  LINE_BREAKS = RichMessages::Types::Options::LINE_BREAKS

  BODY_INVALID = "A enquete precisa de uma pergunta no texto da mensagem, com até #{BODY_MAX} caracteres.".freeze
  OPTIONS_INVALID = "A enquete precisa de #{OPTIONS_MIN} a #{OPTIONS_MAX} opções.".freeze
  OPTION_INVALID = 'Cada opção da enquete precisa de um identificador e de um título, em texto.'.freeze
  ID_INVALID = "O identificador de uma opção da enquete precisa ter até #{ID_MAX} caracteres, sem \"#{ID_FORBIDDEN}\".".freeze
  TITLE_INVALID = "O título de uma opção da enquete precisa ter até #{TITLE_MAX} caracteres, em uma linha só.".freeze
  ID_REPEATED = 'Duas opções da enquete têm o mesmo identificador.'.freeze
  TITLE_REPEATED = 'Duas opções da enquete têm o mesmo título.'.freeze
  MULTIPLE_INVALID = 'O campo multiple da enquete precisa ser verdadeiro ou falso.'.freeze
  # Na versão em texto, o aviso de que dá para marcar mais de uma (em português, como as mensagens deste arquivo; o
  # painel monta o mesmo texto na prévia: montarMensagem.js).
  MULTIPLE_HINT = 'Pode escolher mais de uma'.freeze

  def initialize(payload)
    @options = payload['options']
    @multiple = payload['multiple']
  end

  def error_for(body)
    return BODY_INVALID if body.to_s.strip.empty? || body.length > BODY_MAX
    return OPTIONS_INVALID unless options_count?

    @options.lazy.filter_map { |option| option_error(option) }.first || repetition_error || multiple_error
  end

  # A Cloud API não tem enquete: a pergunta e as opções numeradas, como texto.
  def whatsapp_cloud_payload(body)
    { type: 'text', text: { body: [body.presence, fallback_text(body)].compact.join("\n\n"), preview_url: false } }
  end

  # As opções numeradas, uma por linha; com `multiple`, a linha MULTIPLE_HINT no fim.
  def fallback_text(_body)
    lines = @options.map.with_index(1) { |option, number| "#{number}. #{option['title']}" }
    lines << MULTIPLE_HINT if @multiple == true
    lines.join("\n")
  end

  private

  def options_count?
    @options.is_a?(Array) && @options.size.between?(OPTIONS_MIN, OPTIONS_MAX)
  end

  def option_error(option)
    return OPTION_INVALID unless option.is_a?(Hash) && filled_text?(option['id']) && filled_text?(option['title'])
    return ID_INVALID unless valid_id?(option['id'])

    TITLE_INVALID unless valid_title?(option['title'])
  end

  def valid_id?(id)
    id.length <= ID_MAX && id.exclude?(ID_FORBIDDEN)
  end

  def valid_title?(title)
    title.length <= TITLE_MAX && LINE_BREAKS.none? { |line_break| title.include?(line_break) }
  end

  def repetition_error
    return ID_REPEATED unless @options.pluck('id').uniq.size == @options.size

    TITLE_REPEATED unless @options.map { |option| option['title'].strip }.uniq.size == @options.size
  end

  def multiple_error
    MULTIPLE_INVALID unless @multiple.nil? || @multiple == true || @multiple == false
  end

  def filled_text?(value)
    value.is_a?(String) && value.strip.present?
  end
end
