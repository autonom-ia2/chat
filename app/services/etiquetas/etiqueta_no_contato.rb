# Põe ou tira uma etiqueta do WhatsApp do celular num contato (#1823, F1b): no contato e na conversa não resolvida mais
# recente dele na caixa (aberta ou pendente; adiada e resolvida ficam fora). Chamado pelo Etiquetas::AplicarEventoDoCelular
# dentro da transação que trava a correspondência, então os eventos da mesma etiqueta passam um de cada vez.
# - Contato: pelo telefone (E.164) entre os contatos da caixa; na falta, pelo chat id (source_id do ContactInbox ou os
#   atributos onde o conector WAHA guarda o chat id, Waha::ContactChatId). Não acha: nada muda (fica só o log de quem chama).
# - Ordem: o `at` do último vinculada/desvinculada aplicado no contato fica em Etiquetas::DoCelularNoContato; evento mais
#   velho é descartado.
# - As etiquetas do contato e da conversa são lidas e gravadas sob trava da linha (with_lock): outra etiqueta posta ao
#   mesmo tempo no mesmo contato não se perde.
# - Quando a conversa muda de fato, ela ganha a nota de atividade "O WhatsApp do celular adicionou/removeu a etiqueta X"
#   (protótipo aprovado), no idioma da conta e no mesmo formato das notas de etiqueta do Chatwoot. X é o nome legível:
#   nome livre, senão o nome do celular, senão o derivado do título. Sem mudança, sem nota; no contato, nunca.
# Devolve :aplicado, ou o motivo do descarte (texto) para o log.
class Etiquetas::EtiquetaNoContato
  CONVERSA_EM_ANDAMENTO = %i[open pending].freeze
  CHAVES_DO_CHAT_ID = [Waha::ContactChatId::CHAT_ID, Waha::ContactChatId::JID, Waha::ContactChatId::LID].freeze

  def initialize(registro:, evento:, at:)
    @registro = registro
    @evento = evento
    @at = at
    @inbox = registro.inbox
  end

  def aplicar(operacao)
    contato = contato_do_evento
    return 'contato não encontrado' if contato.nil?

    vinculo = Etiquetas::DoCelularNoContato.find_or_initialize_by(etiqueta_do_celular: @registro, contact: contato)
    return "mais velho que o último aplicado no contato (#{vinculo.evento_em.iso8601})" if mais_velho?(vinculo)

    vinculo.update!(vinculada: operacao == :adicionar, evento_em: @at)
    trocar_etiqueta(contato, operacao)
    conversa = conversa_em_andamento_de(contato)
    anotar(conversa, operacao) if conversa && trocar_etiqueta(conversa, operacao)
    :aplicado
  end

  private

  def mais_velho?(vinculo)
    vinculo.persisted? && @at < vinculo.evento_em
  end

  def titulo
    @registro.label.title
  end

  # Devolve true quando as etiquetas mudaram.
  def trocar_etiqueta(registro, operacao)
    registro.with_lock do
      atuais = registro.label_list.to_a
      novas = operacao == :adicionar ? atuais | [titulo] : atuais - [titulo]
      next false if novas.sort == atuais.sort

      registro.update_labels(novas)
      true
    end
  end

  def anotar(conversa, operacao)
    chave = operacao == :adicionar ? 'adicionada' : 'removida'
    conteudo = I18n.with_locale(idioma_da_conta) do
      I18n.t("etiquetas_do_celular.atividade.#{chave}", etiqueta: nome_legivel)
    end
    Conversations::ActivityMessageJob.perform_later(
      conversa, { account_id: conversa.account_id, inbox_id: conversa.inbox_id, message_type: :activity, content: conteudo }
    )
  end

  def idioma_da_conta
    locale = @inbox.account.locale.presence&.to_sym
    I18n.available_locales.include?(locale) ? locale : I18n.default_locale
  end

  # Mesma ordem do painel (helper nomeDaEtiqueta.js): nome livre → nome do celular → derivado do título
  # ("aguardando_retorno" vira "Aguardando retorno"), sem regex.
  def nome_legivel
    Etiquetas::Nome.find_by(label: @registro.label)&.nome.presence || @registro.nome.presence || nome_do_titulo
  end

  def nome_do_titulo
    palavras = titulo.split('_').compact_blank.join(' ')
    palavras[0].to_s.upcase + palavras[1..].to_s
  end

  def conversa_em_andamento_de(contato)
    @inbox.conversations.where(contact: contato, status: CONVERSA_EM_ANDAMENTO)
          .order(last_activity_at: :desc, id: :desc).first
  end

  def contato_do_evento
    contato_pelo_telefone || contato_pelo_chat_id
  end

  def contatos_da_caixa
    @inbox.account.contacts.joins(:contact_inboxes).where(contact_inboxes: { inbox_id: @inbox.id }).order(:id)
  end

  def contato_pelo_telefone
    telefone = @evento[:contact_phone].to_s.strip
    return if telefone.empty?

    telefone = "+#{telefone}" unless telefone.start_with?('+')
    contatos_da_caixa.find_by(phone_number: telefone)
  end

  def contato_pelo_chat_id
    chat_id = @evento[:chat_id].to_s.strip
    return if chat_id.empty?

    contatos_da_caixa.find_by(contact_inboxes: { source_id: chat_id }) ||
      CHAVES_DO_CHAT_ID.lazy.filter_map do |chave|
        contatos_da_caixa.find_by('contacts.custom_attributes ->> :chave = :valor', chave: chave, valor: chat_id)
      end.first
  end
end
