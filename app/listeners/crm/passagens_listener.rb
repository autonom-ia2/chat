# Registro de passagens (#1606): o escritor das trocas de PESSOA da conversa e da devolução pela tela
# (Crm::Passagens::Atribuicao), e o encerramento na conversa resolvida. No despacho SÍNCRONO (SyncDispatcher): depois
# do commit, na mesma requisição ou job de quem mudou, com a troca que a conversa prendeu no save.
#
# Uma falha aqui não desfaz a troca, que já está gravada: vai para o rastreador de erros e para o log, só com ids.
class Crm::PassagensListener < BaseListener
  def assignee_changed(event)
    conversation, = extract_conversation_and_account(event)
    return if conversation.blank?

    # Solta sempre, mesmo com o CRM desligado: uma troca velha presa no objeto não pode valer para o próximo save.
    troca = conversation.soltar_troca_da_passagem
    registrar(conversation, 'troca') { Crm::Passagens::Atribuicao.troca!(conversation, troca) }
  end

  def conversation_resolved(event)
    conversation, = extract_conversation_and_account(event)
    return if conversation.blank?

    registrar(conversation, 'resolvida') { Crm::Passagens::Atribuicao.resolvida!(conversation, Current.user) }
  end

  private

  def registrar(conversation, evento)
    return unless Crm::Config.enabled?

    yield
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
    Rails.logger.error("[crm][passagem] nao_registrada evento=#{evento} conversa=#{conversation.id} erro=#{e.class}")
  end
end
