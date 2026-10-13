# Formulário do WhatsApp, o Flow (chat#1473, P2):
#   { "type": "flow", "flow_id": "1234567890", "cta": "Iniciar", "token": "<gerado por quem envia>", "screen": "LOGIN",
#     "data": { ... }, "mode": "draft", "header": "Proposta", "footer": "Leva um minuto", "name": "Login do corretor" }
# `data`, `mode`, `header`, `footer` e `name` são opcionais. `name` é só para a conversa do atendente (o painel não
# sabe o nome do formulário pelo `flow_id`) e não vai para a Meta. `mode` só aceita "draft" (sem ele, o publicado).
# Sai sempre com `flow_action: navigate`, para a tela `screen`, e `flow_message_version: "3"`.
# `flow_id` é o identificador que a Meta mostra, só dígitos, em texto: número em JSON é recusado, porque acima de
# 2^53 ele perde precisão no caminho.
# `data` vai como veio para a primeira tela. Ele fica em `content_attributes`, que chega aos webhooks da conta, ao
# robô, ao painel e à API: nunca deve levar credencial nem dado pessoal. A bolha do atendente não o mostra.
# Limites: botão até 30 caracteres (o que a Meta recomenda para o `flow_cta`; emoji é aceito, ver o doc de auditoria);
# corpo até 1024, cabeçalho de texto, rodapé e nome até 60, como no botão de link (para o Flow a Meta não publica
# esses números); `data` até DATA_MAX bytes.
# Não há versão em texto: só sai pelo WhatsApp oficial com a janela aberta.
class RichMessages::Types::Flow
  CTA_MAX = 30
  BODY_MAX = 1024
  EDGE_MAX = 60
  # A Meta não publica teto para os dados iniciais. 8 KB (no JSON serializado) cabem dezenas de campos de
  # preenchimento da primeira tela, bem acima do que os fluxos do n8n mandam hoje, e seguram o tamanho de
  # `content_attributes`, que é copiado para cada webhook, cada evento do painel e cada reenvio.
  DATA_MAX = 8 * 1024
  MESSAGE_VERSION = '3'.freeze
  ACTION = 'navigate'.freeze
  DRAFT_MODE = 'draft'.freeze
  DIGITS = '0-9'.freeze
  LINE_BREAKS = ["\n", "\r"].freeze

  BODY_BLANK = 'O formulário precisa de um texto na mensagem.'.freeze
  BODY_TOO_LONG = "O texto da mensagem com formulário passa de #{BODY_MAX} caracteres.".freeze
  FLOW_ID_INVALID = 'O identificador do formulário (flow_id) precisa ser um texto só com dígitos, como a Meta o mostra.'.freeze
  CTA_BLANK = 'O formulário está sem o texto do botão.'.freeze
  CTA_TOO_LONG = "O texto do botão do formulário passa de #{CTA_MAX} caracteres.".freeze
  CTA_MULTILINE = 'O texto do botão do formulário precisa ficar em uma linha só.'.freeze
  TOKEN_INVALID = 'O formulário está sem o token (flow_token), em texto e em uma linha só.'.freeze
  SCREEN_INVALID = 'O formulário está sem a tela inicial (screen), em texto e em uma linha só.'.freeze
  DATA_INVALID = 'Os dados iniciais do formulário precisam ser um objeto com ao menos um campo.'.freeze
  DATA_TOO_LARGE = "Os dados iniciais do formulário passam de #{DATA_MAX / 1024} KB.".freeze
  MODE_INVALID = 'O modo do formulário só pode ser "draft" (rascunho); sem ele, vai o formulário publicado.'.freeze
  HEADER_INVALID = "O cabeçalho do formulário precisa ser um texto de até #{EDGE_MAX} caracteres, em uma linha só.".freeze
  FOOTER_INVALID = "O rodapé do formulário precisa ser um texto de até #{EDGE_MAX} caracteres, em uma linha só.".freeze
  NAME_INVALID = "O nome do formulário precisa ser um texto de até #{EDGE_MAX} caracteres, em uma linha só.".freeze

  def self.text_version? = false

  def initialize(payload)
    @flow_id, @cta, @token, @screen, @data, @mode, @header, @footer, @name =
      payload.values_at('flow_id', 'cta', 'token', 'screen', 'data', 'mode', 'header', 'footer', 'name')
  end

  def error_for(body)
    body_error(body) || required_error || data_error || mode_error || edge_error
  end

  # https://developers.facebook.com/docs/whatsapp/flows/guides/sendingaflow
  def whatsapp_cloud_payload(body)
    {
      type: 'interactive',
      interactive: {
        type: 'flow',
        header: (@header && { type: 'text', text: @header }),
        body: { text: body },
        footer: (@footer && { text: @footer }),
        action: { name: 'flow', parameters: parameters }
      }.compact
    }
  end

  # Parte da interface dos tipos; nunca é usada, porque o Flow não tem versão em texto (`self.text_version?`).
  def fallback_text(_body)
    ''
  end

  private

  def parameters
    {
      flow_message_version: MESSAGE_VERSION,
      flow_token: @token,
      flow_id: @flow_id,
      flow_cta: @cta,
      flow_action: ACTION,
      flow_action_payload: { screen: @screen, data: @data }.compact,
      mode: @mode
    }.compact
  end

  def required_error
    flow_id_error || cta_error || field_error(@token, TOKEN_INVALID) || field_error(@screen, SCREEN_INVALID)
  end

  def body_error(body)
    return BODY_BLANK if body.blank?

    BODY_TOO_LONG if body.length > BODY_MAX
  end

  def flow_id_error
    FLOW_ID_INVALID unless @flow_id.is_a?(String) && @flow_id.present? && @flow_id.delete(DIGITS).empty?
  end

  def cta_error
    return CTA_BLANK unless text?(@cta)
    return CTA_MULTILINE unless one_line?(@cta)

    CTA_TOO_LONG if @cta.length > CTA_MAX
  end

  def field_error(value, error)
    error unless text?(value) && one_line?(value)
  end

  def data_error
    return if @data.nil?
    return DATA_INVALID unless @data.is_a?(Hash) && @data.present?

    DATA_TOO_LARGE if @data.to_json.bytesize > DATA_MAX
  end

  def mode_error
    MODE_INVALID unless @mode.nil? || @mode == DRAFT_MODE
  end

  def edge_error
    short_line_error(@header, HEADER_INVALID) || short_line_error(@footer, FOOTER_INVALID) || short_line_error(@name, NAME_INVALID)
  end

  def short_line_error(text, error)
    error unless text.nil? || (text?(text) && text.length <= EDGE_MAX && one_line?(text))
  end

  def text?(value)
    value.is_a?(String) && value.strip.present?
  end

  def one_line?(text)
    LINE_BREAKS.none? { |line_break| text.include?(line_break) }
  end
end
