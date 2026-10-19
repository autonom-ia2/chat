# #1865 — antes de enviar pelo WhatsApp API (WAHA), o contato fica salvo na agenda do aparelho, como no WhatsApp Web, que
# só manda para quem a pessoa conhece. Atrás da flag `whatsapp_agenda_do_contato`.
#
# - Quem decide é o celular: antes de salvar, lê o nome que está na agenda (`name`; o `pushname` é o nome que a pessoa
#   pôs no WhatsApp dela e não conta). Vazio: salva. Igual ao do chat2you: nada a fazer. O nome que nós mesmos salvamos
#   antes (marca no Redis): atualiza. Qualquer outro foi o dono que salvou: não toca.
# - A agenda é guardada pelo número (`<número>@c.us`), nunca pelo `@lid`, mesmo quando o envio sai pelo `@lid`. Conferido
#   no motor em 19/10/2026: nas sessões 5511941010656 (361 contatos com nome) e hybrid-551142155355 (331), todos estão
#   em `@c.us`, e a leitura pelo `@lid` do mesmo contato volta com o nome vazio. Ler pelo `@lid` faria a agenda parecer
#   vazia e sobrescreveria o nome do dono.
# - O Redis só evita repetir a leitura: guarda um resumo (HMAC) do nome decidido. Sem a marca (Redis perdido), um nome
#   diferente na agenda conta como do dono.
# - Para a segunda mensagem não passar na frente da primeira enquanto esta salva o contato, o ConversaCanal::EnvioEmOrdem
#   envolve este salvamento e o envio; `a_fazer?` diz se há trabalho.
# - Sem agenda: grupo, transmissão e canal. Sem nome, ou nome que é o próprio telefone: nada a salvar.
# - Nunca trava o envio: qualquer falha vira log (só a classe; a mensagem do erro traz URL e corpo), o envio segue e o
#   contato fica FALHA_TTL sem nova tentativa (motor lento não atrasa cada mensagem). Um 404 do motor também é falha,
#   nunca "agenda vazia": contato que o motor não conhece responde 200 com o nome vazio (visto em 19/10), e um 404 pode
#   ser sessão parada ou rota que não existe; tratar como vazio renomearia o contato do dono.
class Waha::AgendaDoContato
  FLAG = 'whatsapp_agenda_do_contato'.freeze
  TIMEOUT = 5
  CACHE_TTL = 180.days.to_i
  FALHA_TTL = 10.minutes.to_i
  PN_SUFFIX = '@c.us'.freeze
  SEM_AGENDA = %w[@g.us @broadcast @newsletter @lid].freeze
  NOSSO = 's:'.freeze
  DO_DONO = 'x:'.freeze
  FALHOU = 'f:'.freeze

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
    return unless a_fazer?

    decidir(::Redis::Alfred.get(chave))
  rescue StandardError => e
    registrar_falha(e)
  end

  # Há o que fazer: contato com agenda e nome, ainda não decidido para este nome e sem falha recente.
  def a_fazer?
    return false unless aplicavel?

    marca = ::Redis::Alfred.get(chave)
    marca != FALHOU && [NOSSO + resumo(nome), DO_DONO + resumo(nome)].exclude?(marca)
  end

  private

  def registrar_falha(error)
    Rails.logger.info("[waha][agenda] contato não salvo session=#{@session} contact=#{@contact&.id} #{error.class}")
    ::Redis::Alfred.setex(chave, FALHOU, FALHA_TTL)
  rescue StandardError => e
    Rails.logger.info("[waha][agenda] marca de falha não gravada session=#{@session} #{e.class}")
  end

  def decidir(marca)
    na_agenda = nome_na_agenda
    return marcar(DO_DONO) unless na_agenda.blank? || na_agenda == nome || marca == NOSSO + resumo(na_agenda)

    salvar unless na_agenda == nome
    marcar(NOSSO)
  end

  def nome_na_agenda
    @client.contact(session: @session, chat_id: @chat_id, timeout: TIMEOUT).to_h['name'].to_s.strip
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

  # HMAC com a chave do app: a marca no Redis não guarda o nome nem um resumo que dê para adivinhar por dicionário.
  def resumo(texto)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, texto)[0, 32]
  end

  def marcar(dono)
    ::Redis::Alfred.setex(chave, dono + resumo(nome), CACHE_TTL)
  end

  def chave
    "waha:agenda:#{@session}:#{@chat_id}"
  end
end
