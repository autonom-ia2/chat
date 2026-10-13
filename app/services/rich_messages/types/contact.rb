# Cartão de contato (chat#1473, P5): um contato com nome e telefone.
#   { "type": "contact", "name": "Recepção da Unidade Centro", "phone": "+55 11 4000-0473", "wa_id": "551140000473" }
# `name` obrigatório, em uma linha, até 100 caracteres (a Meta não dá limite; o número é nosso). `phone` obrigatório,
# começando com `+` e o código do país, de 8 a 15 dígitos (o máximo do padrão internacional), aceitando espaço,
# hífen, ponto e parênteses; sai para a Meta como foi escrito. `wa_id` opcional, só dígitos: com ele o cliente vê
# os botões de conversa; sem ele, a Meta mostra "Convidar para o WhatsApp".
# Na Meta o formato não tem corpo: a mensagem vai com `content` vazio, e corpo não vazio é recusado.
class RichMessages::Types::Contact
  NAME_MAX = 100
  DIGITS = '0-9'.freeze
  PHONE_CHARACTERS = '0-9 ().-'.freeze
  PHONE_DIGITS = (8..15)
  LINE_BREAKS = ["\n", "\r"].freeze

  BODY_NOT_ALLOWED = 'O contato vai sem texto: deixe a mensagem vazia e ponha nome e telefone nos campos dele.'.freeze
  NAME_INVALID = "O nome do contato precisa ser um texto de até #{NAME_MAX} caracteres, em uma linha só.".freeze
  PHONE_INVALID = 'O telefone do contato precisa começar com + e o código do país, com 8 a 15 dígitos (ex.: +55 11 4000-0473).'.freeze
  WA_ID_INVALID = 'O WhatsApp do contato (wa_id) precisa ter só números, de 8 a 15 dígitos, sem o +.'.freeze

  def initialize(payload)
    @name = payload['name']
    @phone = payload['phone']
    @wa_id = payload['wa_id']
  end

  def error_for(body)
    return BODY_NOT_ALLOWED if body.present?
    return NAME_INVALID unless name?
    return PHONE_INVALID unless phone?

    WA_ID_INVALID unless @wa_id.nil? || wa_id?
  end

  # https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/contacts-messages
  # Só `formatted_name` é obrigatório na Meta; `first_name` vai junto para o aparelho do cliente salvar com nome.
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

  def wa_id?
    @wa_id.is_a?(String) && @wa_id.delete(DIGITS).empty? && PHONE_DIGITS.cover?(@wa_id.length)
  end
end
