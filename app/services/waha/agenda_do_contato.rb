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
# - Uma decisão por contato de cada vez (trava curta no Redis): a segunda mensagem ao mesmo contato espera a primeira
#   terminar, para não sair na frente dela.
# - Sem agenda: grupo, transmissão e canal. Sem nome, ou nome que é o próprio telefone: nada a salvar.
# - Nunca trava o envio: qualquer falha vira log (só a classe; a mensagem do erro traz URL e corpo), o envio segue e o
#   contato fica FALHA_TTL sem nova tentativa (motor lento não atrasa cada mensagem).
class Waha::AgendaDoContato
  FLAG = 'whatsapp_agenda_do_contato'.freeze
  TIMEOUT = 5
  CACHE_TTL = 180.days.to_i
  FALHA_TTL = 10.minutes.to_i
  TRAVA_TTL = (TIMEOUT * 3).seconds.to_i
  ESPERA_MAXIMA = TIMEOUT * 2
  PASSO_DA_ESPERA = 0.2
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
    return unless aplicavel? && pendente?
    return esperar_a_outra unless travar

    begin
      decidir(::Redis::Alfred.get(chave))
    ensure
      ::Redis::Alfred.delete(chave_da_trava)
    end
  rescue StandardError => e
    ::Redis::Alfred.setex(chave, FALHOU, FALHA_TTL)
    Rails.logger.info("[waha][agenda] contato não salvo session=#{@session} contact=#{@contact&.id} #{e.class}")
  end

  private

  # Nada a fazer: já decidido para este nome, ou falhou há pouco.
  def pendente?
    marca = ::Redis::Alfred.get(chave)
    marca != FALHOU && [NOSSO + resumo(nome), DO_DONO + resumo(nome)].exclude?(marca)
  end

  def decidir(marca)
    na_agenda = nome_na_agenda
    return marcar(DO_DONO) unless na_agenda.blank? || na_agenda == nome || marca == NOSSO + resumo(na_agenda)

    salvar unless na_agenda == nome
    marcar(NOSSO)
  end

  # Contato que o motor não conhece responde vazio; 404 conta como vazio também.
  def nome_na_agenda
    @client.contact(session: @session, chat_id: @chat_id, timeout: TIMEOUT).to_h['name'].to_s.strip
  rescue Waha::Client::NotFound
    ''
  end

  def salvar
    primeiro, resto = nome.split(' ', 2)
    @client.upsert_contact(session: @session, chat_id: @chat_id, first_name: primeiro, last_name: resto.to_s, timeout: TIMEOUT)
  end

  def travar
    ::Redis::Alfred.set(chave_da_trava, '1', nx: true, ex: TRAVA_TTL)
  end

  # Outra mensagem ao mesmo contato está decidindo: espera ela acabar (até ESPERA_MAXIMA) e segue sem repetir.
  def esperar_a_outra
    limite = ESPERA_MAXIMA.seconds.from_now
    Kernel.sleep(PASSO_DA_ESPERA) while ::Redis::Alfred.exists?(chave_da_trava) && Time.current < limite
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

  def chave_da_trava
    "#{chave}:trava"
  end
end
