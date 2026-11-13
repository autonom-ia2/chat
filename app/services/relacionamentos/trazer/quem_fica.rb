# "Trazer minha lista" (#2896): das pessoas que uma lista criou, quais o "Desfazer" não apaga. A lista só leva embora
# quem ela trouxe e em quem ninguém tocou. Fica quem:
#
# - tem conversa;
# - tem card no funil, como a pessoa do card ou como quem pediu (solicitante);
# - tem nota escrita na ficha, retorno marcado ou etiqueta (saem junto com a pessoa, e foi alguém que os pôs lá; a
#   importação de contatos não põe etiqueta em ninguém);
# - teve a ficha editada depois da lista: o nome, o telefone, o e-mail, a cidade, a empresa ou uma informação já não são
#   os que a linha deixou (Relacionamentos::Trazer::PessoaCriada). Só dá para saber de quem a lista anotou;
# - tem convite de agendamento, é convidada de uma reunião ou a IA já guardou memória dela;
# - tem seguro na carteira (Carteira::Apolice): a apólice, a história e o PDF dela sairiam junto com a pessoa;
# - veio também da prospecção ou de um formulário de anúncio (o lead perderia a pessoa);
# - recebeu, ou está na fila de, uma campanha (WhatsApp ou SMS, e-mail, WhatsApp Oficial);
# - está em outra importação: outra lista trazida, um Público ou uma base de campanha. A lista que já foi desfeita não
#   segura ninguém: quem trouxe a mesma planilha duas vezes e desfez uma consegue desfazer a outra. A base de campanha
#   que só teve as etiquetas desfeitas continua segurando (Relacionamentos::Trazer::Situacao.desfeitas);
# - entrou num Público montado pelas conversas;
# - recusou mensagens (opted_out_at), recusou avisos de agendamento ou está bloqueada. Apagar a pessoa apagaria a
#   recusa junto, e a próxima pessoa criada com o mesmo telefone voltaria a receber.
#
# Quem já não existe (apagada à mão, ou mesclada em outra pessoa) não sai nem fica: é pulada.
#
# A prévia e o Desfazer leem por aqui, em blocos, então o que a prévia promete é o que o Desfazer faz. O Desfazer ainda
# pergunta de novo antes de apagar: por `entre`, de poucas em poucas pessoas, e por `tem_conversa?`, pessoa a pessoa
# (Relacionamentos::Trazer::Desfazer). Quem ganhou conversa enquanto o bloco andava fica.
#
# Toda fonte é lida só dentro da conta, mesmo as que não têm a coluna da conta (vão pela campanha, pela importação ou
# pela busca a que pertencem).
class Relacionamentos::Trazer::QuemFica
  BLOCO = 500

  def initialize(importacao)
    @importacao = importacao
    @conta = importacao.account
    @criada = Relacionamentos::Trazer::PessoaCriada.new(importacao)
  end

  # Bloco a bloco, das pessoas que a lista criou e que ainda existem: os ids das que saem e os das que ficam.
  def em_blocos
    criadas.in_batches(of: BLOCO) do |linhas|
      existem = @conta.contacts.where(id: linhas.select(:contact_id)).ids
      ficam = entre(existem)
      yield existem.reject { |id| ficam.include?(id) }, ficam.to_a
    end
  end

  # As linhas das pessoas que a lista criou.
  def criadas
    @importacao.campaign_import_rows.status_imported.where(was_existing_contact: false).where.not(contact_id: nil)
  end

  # ids: pessoas da conta. Devolve o conjunto das que ficam.
  def entre(ids)
    return Set.new if ids.empty?

    seguradas = onde_aparece.flat_map { |registros, coluna| registros.where(coluna => ids).distinct.pluck(coluna) }.to_set
    seguradas.merge(@criada.editadas(ids - seguradas.to_a))
  end

  def fica?(id)
    entre([id]).any?
  end

  # A conversa é o que chega sozinho, a qualquer segundo: o Desfazer pergunta por ela pessoa a pessoa, logo antes de apagar.
  def tem_conversa?(id)
    Conversation.where(da_conta).exists?(contact_id: id)
  end

  private

  # [de onde, coluna com o id da pessoa]
  def onde_aparece
    conversa_funil_e_ficha + campanhas_e_listas + agenda_memoria_e_leads + recusas
  end

  def da_conta
    { account_id: @conta.id }
  end

  def conversa_funil_e_ficha
    [
      [Conversation.where(da_conta), :contact_id],
      [Crm::Card.where(da_conta), :contact_id], [Crm::Card.where(da_conta), :solicitante_contact_id],
      [Note.where(da_conta), :contact_id], [Crm::FollowUp.where(da_conta), :contact_id], [Crm::FollowUpSeries.where(da_conta), :contact_id],
      [ActsAsTaggableOn::Tagging.where(taggable_type: Contact.name), :taggable_id]
    ]
  end

  def campanhas_e_listas
    [
      [CampaignRecipient.where(da_conta), :contact_id],
      [EmailCampaignRecipient.where(email_campaign_id: EmailCampaign.where(da_conta).select(:id)), :contact_id],
      [WhatsappApiCampaignRecipient.where(da_conta), :contact_id],
      [CampaignImportRow.where(campaign_import_id: @conta.campaign_imports.where.not(id: que_nao_seguram).select(:id)), :contact_id],
      [ConversationAudiencePerson.where(search_id: ConversationAudienceSearch.where(da_conta).select(:id)), :contact_id]
    ]
  end

  # As importações que não seguram ninguém: esta e as listas que a conta já desfez.
  def que_nao_seguram
    [@importacao.id] + Relacionamentos::Trazer::Situacao.desfeitas(@conta.campaign_imports).ids
  end

  def agenda_memoria_e_leads
    [
      [Crm::BookingInvite.where(da_conta), :contact_id], [Crm::MeetingGuest.where(da_conta), :contact_id],
      [Crm::MemoriaFato.where(da_conta), :contact_id], [Carteira::Apolice.where(da_conta), :contact_id],
      [Autonomia::Prospecting::Lead.where(da_conta), :contact_id], [Crm::MetaAdsLead.where(da_conta), :contact_id]
    ]
  end

  def recusas
    [
      [Crm::BookingNoticeStop.where(da_conta), :contact_id],
      [@conta.contacts.where.not(opted_out_at: nil).or(@conta.contacts.where(blocked: true)), :id]
    ]
  end
end
