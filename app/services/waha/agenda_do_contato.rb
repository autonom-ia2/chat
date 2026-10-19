# #1865 — antes de enviar pelo WhatsApp API (WAHA), o contato fica salvo na agenda do aparelho, como no WhatsApp Web, que
# só manda para quem a pessoa conhece. Atrás da flag `whatsapp_agenda_do_contato`.
#
# - Quem decide é o celular: antes de salvar, lê o nome que está na agenda (`name`; o `pushname` é o nome que a pessoa
#   pôs no WhatsApp dela e não conta). Vazio: salva. Igual ao do chat2you: nada a fazer. O nome que nós mesmos salvamos
#   antes (marca no Redis): atualiza. Qualquer outro foi o dono que salvou: não toca.
# - O Redis só evita repetir a leitura: guarda o resumo do nome decidido. Sem a marca (Redis perdido), um nome diferente
#   na agenda conta como do dono.
# - Sem agenda: grupo, transmissão, canal e endereço `@lid` (o contato é salvo pelo número). Sem nome, ou nome que é o
#   próprio telefone: nada a salvar.
# - Nunca trava o envio: qualquer falha vira log (só a classe; a mensagem do erro traz URL e corpo) e o envio segue.
class Waha::AgendaDoContato
  FLAG = 'whatsapp_agenda_do_contato'.freeze
  TIMEOUT = 5
  CACHE_TTL = 180.days.to_i
  PN_SUFFIX = '@c.us'.freeze
  SEM_AGENDA = %w[@g.us @broadcast @newsletter @lid].freeze
  NOSSO = 's:'.freeze
  DO_DONO = 'x:'.freeze

  def self.enabled?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # O contato é salvo pelo número (`<número>@c.us`); sem telefone, o jid que o conector guardou.
  def self.chat_id_de(contact)
    digits = contact&.phone_number.to_s.delete('^0-9')
    return "#{digits}#{PN_SUFFIX}" if digits.present?

    Waha::ContactChatId.values(contact, :jid).first
  end

  def initialize(client:, session:, contact:, chat_id: self.class.chat_id_de(contact))
    @client = client
    @session = session
    @contact = contact
    @chat_id = chat_id.to_s
  end

  def garantir
    return unless aplicavel?

    marca = ::Redis::Alfred.get(chave)
    return if [NOSSO + resumo(nome), DO_DONO + resumo(nome)].include?(marca)

    decidir(marca)
  rescue StandardError => e
    Rails.logger.info("[waha][agenda] contato não salvo session=#{@session} contact=#{@contact&.id} #{e.class}")
  end

  private

  def decidir(marca)
    na_agenda = @client.contact(session: @session, chat_id: @chat_id, timeout: TIMEOUT).to_h['name'].to_s.strip
    return marcar(DO_DONO) unless na_agenda.blank? || na_agenda == nome || marca == NOSSO + resumo(na_agenda)

    salvar unless na_agenda == nome
    marcar(NOSSO)
  end

  def salvar
    primeiro, resto = nome.split(' ', 2)
    @client.upsert_contact(session: @session, chat_id: @chat_id, first_name: primeiro, last_name: resto.to_s, timeout: TIMEOUT)
  end

  def aplicavel?
    @session.present? && @chat_id.present? && SEM_AGENDA.none? { |sufixo| @chat_id.end_with?(sufixo) } &&
      nome.present? && !nome_e_telefone?
  end

  # Nome que é só o telefone (o contato criado sem nome): comparado pelos dígitos.
  def nome_e_telefone?
    digitos = nome.delete('^0-9')
    digitos.present? && digitos == @chat_id.delete('^0-9')
  end

  def nome
    @nome ||= @contact&.name.to_s.squish
  end

  def resumo(texto)
    Digest::SHA256.hexdigest(texto)[0, 16]
  end

  def marcar(dono)
    ::Redis::Alfred.setex(chave, dono + resumo(nome), CACHE_TTL)
  end

  def chave
    "waha:agenda:#{@session}:#{@chat_id}"
  end
end
