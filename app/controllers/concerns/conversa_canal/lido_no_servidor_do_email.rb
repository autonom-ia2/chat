# #1870 — Prepend em Api::V1::Accounts::ConversationsController: o "lido" da caixa de e-mail nos dois sentidos com o
# servidor IMAP do cliente. Só com a flag `email_lido_sincronizado` e caixa com IMAP (ConversaCanal::EmailLido.sincroniza?);
# fora disso, tudo segue pelo Chatwoot (super).
# - Abrir a conversa no painel (update_last_seen com read_receipt, o mesmo gancho de ConversaCanal::LeituraAoAbrir) marca
#   os e-mails dela como lidos no servidor, por job.
# - "Marcar como não lida" (unread) tira o \Seen do último e-mail recebido no servidor, por job.
# - Os pedidos vão para a fila da caixa; um job por caixa escreve todos (ConversaCanal::EmailLidoNoServidorJob).
# - Na caixa que sincroniza, update_last_seen_on_conversation é ConversaCanal::LidoDaConversa, o mesmo serviço que a
#   importação usa quando o lido muda no servidor do cliente (mesmos efeitos: colunas e contadores).
# - Só atendente (User). Nada daqui muda a resposta: qualquer falha vira log.
module ConversaCanal::LidoNoServidorDoEmail
  def update_last_seen
    super
    agendar_email_lido if ActiveModel::Type::Boolean.new.cast(params[:read_receipt])
  end

  # A marca de "não lida pendente" do último recebido entra ANTES do super: a importação que rodar no meio não conta a
  # passagem para lido dele e não desfaz o "não lida" (ConversaCanal::EmailLido.nao_lida_pendente!). Se o super falhar,
  # a marca sai antes de o erro seguir.
  def unread
    servico = preparar_email_nao_lido
    super
    agendar_email_nao_lido(servico)
  rescue StandardError
    desfazer_email_nao_lido(servico)
    raise
  end

  private

  def update_last_seen_on_conversation(last_seen_at, update_assignee)
    return super unless caixa_sincroniza_o_lido?

    ConversaCanal::LidoDaConversa.new(@conversation).marcar!(last_seen_at, atualizar_responsavel: update_assignee)
  end

  def caixa_sincroniza_o_lido?
    email_lido_no_servidor.sincroniza?
  rescue StandardError => e
    registrar_falha_do_email_lido(e)
    false
  end

  def email_lido_no_servidor
    @email_lido_no_servidor ||= ConversaCanal::EmailLidoNoServidor.new(conversation: @conversation)
  end

  def agendar_email_lido
    return unless Current.user.is_a?(User) && email_lido_no_servidor.lido_pendente?

    ConversaCanal::EmailLidoNoServidorJob.agendar(@conversation, ConversaCanal::EmailLidoNoServidorJob::LIDO)
  rescue StandardError => e
    registrar_falha_do_email_lido(e)
  end

  def preparar_email_nao_lido
    servico = email_lido_no_servidor
    return unless Current.user.is_a?(User) && servico.sincroniza?

    servico.preparar_nao_lida
    servico
  rescue StandardError => e
    registrar_falha_do_email_lido(e)
    nil
  end

  def agendar_email_nao_lido(servico)
    return if servico.nil?

    ConversaCanal::EmailLidoNoServidorJob.agendar(@conversation, ConversaCanal::EmailLidoNoServidorJob::NAO_LIDA)
  rescue StandardError => e
    tirar_da_fila_sem_estourar(ConversaCanal::EmailLidoNoServidorJob::NAO_LIDA)
    desfazer_email_nao_lido(servico)
    registrar_falha_do_email_lido(e)
  end

  def tirar_da_fila_sem_estourar(acao)
    ConversaCanal::FilaDoEmailLido.new(@conversation.inbox_id).remover(@conversation.id, acao)
  rescue StandardError => e
    registrar_falha_do_email_lido(e)
  end

  # Sem job agendado, a marca de "não lida pendente" não pode ficar: sai (a importação volta a ver a passagem).
  def desfazer_email_nao_lido(servico)
    servico&.desfazer_nao_lida
  rescue StandardError => e
    registrar_falha_do_email_lido(e)
  end

  def registrar_falha_do_email_lido(error)
    ConversaCanal::FalhaDoEmailLido.registrar(error, account: @conversation.account, inbox_id: @conversation.inbox_id,
                                                     onde: "painel conversation=#{@conversation.id}")
  end
end
