# Cartão de contato (chat#1473, P5): um contato com nome e telefone.
#   { "type": "contact", "name": "Recepção da Unidade Centro", "phone": "+55 11 4000-0473", "wa_id": "551140000473" }
# `name` obrigatório, em uma linha, até 100 caracteres (a Meta não dá limite; o número é nosso). `phone` obrigatório,
# começando com `+` e o código do país, de 8 a 15 dígitos (o máximo do padrão internacional), aceitando espaço,
# hífen, ponto e parênteses; sai para a Meta como foi escrito. `wa_id` opcional, só dígitos: com ele o cliente vê
# os botões de conversa; sem ele, a Meta mostra "Convidar para o WhatsApp". `wa_id` em branco conta como ausente.
# Na Meta o formato não tem corpo: a mensagem vai com `content` vazio, e corpo não vazio é recusado.
class RichMessages::Types::Contact
  NAME_MAX = 100
  DIGITS = '0-9'.freeze
  PHONE_CHARACTERS = '0-9 ().-'.freeze
  PHONE_DIGITS = (8..15)
  # Quebras de linha, inclusive as do Unicode (o tab continua aceito).
  LINE_BREAKS = ["\n", "\r", "\v", "\u0085", "\u2028", "\u2029"].freeze

  BODY_NOT_ALLOWED = 'O contato vai sem texto: deixe a mensagem vazia e ponha nome e telefone nos campos dele.'.freeze
  NAME_INVALID = "O nome do contato precisa ser um texto de até #{NAME_MAX} caracteres, em uma linha só.".freeze
  PHONE_INVALID = 'O telefone do contato precisa começar com + e o código do país, com 8 a 15 dígitos (ex.: +55 11 4000-0473).'.freeze
  WA_ID_INVALID = 'O WhatsApp do contato (wa_id) precisa ter só números, de 8 a 15 dígitos, sem o +.'.freeze
  WA_ID_NOT_TEXT = 'Mande o wa_id do contato como texto, só com dígitos (ex.: "551140000473"), não como número.'.freeze

  def initialize(payload)
    @name = payload['name']
    @phone = payload['phone']
    wa_id = payload['wa_id']
    @wa_id = wa_id unless wa_id.is_a?(String) && wa_id.blank?
  end

  def error_for(body)
    return BODY_NOT_ALLOWED if body.present?
    return NAME_INVALID unless name?
    return PHONE_INVALID unless phone?

    wa_id_error
  end

  # https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/contacts-messages
  # `first_name` vai junto do `formatted_name` para o aparelho do cliente salvar com nome.
  def whatsapp_cloud_payload(_body)
    {
      type: 'contacts',
      contacts: [{ name: { formatted_name: @name, first_name: @name }, phones: [{ phone: @phone, wa_id: @wa_id }.compact] }]
    }
  end

  def fallback_text(_body)
    "#{@name}: #{@phone}"
  end

  private

  def name?
    @name.is_a?(String) && @name.strip.present? && @name.length <= NAME_MAX && LINE_BREAKS.none? { |line_break| @name.include?(line_break) }
  end

  def phone?
    return false unless @phone.is_a?(String) && @phone.start_with?('+')

    number = @phone.delete_prefix('+')
    number.delete(PHONE_CHARACTERS).empty? && PHONE_DIGITS.cover?(number.count(DIGITS))
  end

  def wa_id_error
    return if @wa_id.nil?
    return WA_ID_NOT_TEXT if @wa_id.is_a?(Numeric)

    WA_ID_INVALID unless @wa_id.is_a?(String) && @wa_id.delete(DIGITS).empty? && PHONE_DIGITS.cover?(@wa_id.length)
  end
end
