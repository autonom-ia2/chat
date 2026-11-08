# #2211 — as caixas em que a pessoa pode começar conversa com o telefone ou o e-mail novo da busca da lista.
#
# São as do InboxPolicy#show?, que o create da conversa confere (authorize @inbox, :show?). O inbox_view de função
# personalizada lista todas as caixas da conta no index de caixas, mas não deixa começar conversa numa caixa de que a
# pessoa não é membro: oferecer essa caixa gravava o contato e o create da conversa respondia 403. Uma consulta só: o
# Scope do InboxPolicy é o mesmo conjunto que o show? confere (assigned_inboxes: todas as da conta para o administrador,
# as que atende para o agente).
class SearchService::CaixasParaComecar
  def initialize(contexto_de_acesso:, conta:)
    @contexto_de_acesso = contexto_de_acesso
    @conta = conta
  end

  def ids
    @ids ||= @conta.inboxes.where(id: InboxPolicy::Scope.new(@contexto_de_acesso, Inbox).resolve.select(:id)).order(:id).ids
  end

  # #2257 — no telefone novo, as caixas do WhatsApp em que a primeira mensagem pode ser texto livre (Híbrido pronto), para
  # a tela não começar pedindo modelo. A regra é a da nova conversa (WhatsappHybrid::NewConversation), com um contato em
  # memória, sem gravar: dele a regra só usa o telefone. Só entre as caixas em que a pessoa pode começar conversa; para
  # WhatsApp, o ContactableInboxesService só pede o telefone, que aqui sempre existe.
  def com_texto_livre(numero)
    contato = Contact.new(account: @conta, phone_number: numero)
    @conta.inboxes.where(id: ids, channel_type: 'Channel::Whatsapp').order(:id).select do |caixa|
      WhatsappHybrid::NewConversation.new(inbox: caixa, contact: contato).free_text_available?
    end.map(&:id)
  end
end
