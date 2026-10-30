# Exclusão da conta (#2133): apaga o que o fork guarda da conta, em lotes, para o DeleteObjectJob.
#
# As associações da conta são `dependent: :destroy_async`, que só enfileiram a exclusão depois do commit. As tabelas do
# fork apontam para a conta (e umas para as outras) com chave estrangeira sem cascata, então o DELETE da conta esbarrava
# nelas e o job falhava com a conta inteira no banco. Aqui elas saem antes, em lotes de LOTE linhas e na ordem das chaves:
# cada tabela vem antes das que ela referencia. Entram também:
# - as tabelas com cascata a partir da conta, para o DELETE final da conta não apagar dezenas de tabelas num comando só;
# - as tabelas da conta sem chave estrangeira (uso de IA, conversões da Meta, horários), que ninguém mais apagaria.
# O job começa por `parar_a_conta` (suspende e cancela campanhas agendadas). Depois chama `antes_do_pre_apagar` antes
# do pré-apagar do upstream (conversas, contatos, caixas): ali saem só as
# tabelas com chave sem cascata para o que o pré-apagar apaga (whatsapp_api_campaign_recipients.message_id faria o job
# das mensagens desistir). O resto sai em `perform`, depois do pré-apagar e logo antes do `destroy!`, para os callbacks
# das caixas (vínculo do agente, conexão do Híbrido) rodarem como antes. Linha criada entre o `perform` e o `destroy!`
# ainda pode barrar o DELETE; o job falha e a próxima tentativa a apaga. O `exclusao_da_conta_spec` lê as chaves e as
# colunas do banco e falha quando aparece tabela nova que barraria a exclusão, que ficaria sem quem a apague ou que
# levaria anexo pela cascata.
#
# `delete_all` não roda callbacks. Dos efeitos deles, ficam os que importam:
# - anexos (Active Storage): as linhas saem junto do lote e o arquivo vai para o PurgeJob quando nenhum outro anexo
#   usa o mesmo blob;
# - tokens de integração do CRM: o `access_token` (o bearer) sai junto, para não sobrar credencial de dono apagado;
#   os do MCP saem pelo `revoke!`, que apaga também o usuário técnico deles.
# A conexão do WhatsApp Híbrido não está aqui: ela sai com a caixa (`Inbox has_one ..., dependent: :destroy`), e o
# callback dela desliga a sessão no WAHA.
# Reunião marcada no Google ou na Microsoft não é cancelada: a conta está saindo, e o evento continua no calendário de
# quem a marcou.
# A classe passa do limite de linhas por causa de ETAPAS, que é dado: uma linha por tabela da conta, e cresce a cada
# tabela nova (o exclusao_da_conta_spec cobra). A lógica continua curta.
class Autonomia::ExclusaoDaConta # rubocop:disable Metrics/ClassLength
  LOTE = 5_000

  # [modelo, como achar as linhas da conta]. A ordem é a das chaves estrangeiras: filho antes do pai.
  ETAPAS = [
    # Decisões, passagens e memória apontam para card, funil e conversa.
    ['Autonomia::DecisorDecisao', :por_conta],
    ['Autonomia::Decisor', :por_conta],
    ['Crm::Passagem', :por_conta],
    ['Crm::SubjectDecision', :por_conta],
    ['Crm::MemoriaFato', :por_conta],
    ['Crm::MetaAdsCommentAction', :por_conta],
    ['Crm::MetaAdsCommentCare', :por_conta],
    ['Crm::MemoriaChave', :por_conta],
    # Card e o que pendura nele.
    ['Crm::StageAutomationExecution', :por_conta],
    ['Crm::AiStageSuggestion', :por_conta],
    ['Crm::Activity', :por_conta],
    ['Crm::CardConversation', :por_conta],
    ['Crm::MeetingGuest', :por_conta],
    ['Crm::Meeting', :por_conta],
    ['Crm::FollowUp', :por_conta],
    ['Crm::FollowUpSeries', :por_conta],
    ['Crm::AiUsageEvent', :por_conta],
    ['Crm::MetaConversionEvent', :por_conta],
    ['Crm::GoogleConversionEvent', :por_conta],
    ['Crm::MetaAdsLead', :por_conta],
    ['Autonomia::Prospecting::ListLead', :por_conta],
    ['Autonomia::Prospecting::Lead', :por_conta],
    ['Autonomia::Prospecting::List', :por_conta],
    ['Autonomia::Prospecting::Search', :por_conta],
    ['Autonomia::Prospecting::SavedPreset', :por_conta],
    ['Autonomia::Prospecting::Setting', :por_conta],
    ['Autonomia::Prospecting::ScoringProfileAccount', :por_conta],
    ['Crm::Card', :por_conta],
    # Funil, etapas e o que aponta para eles.
    ['Crm::StageAutomationStep', :por_conta],
    ['Crm::StageAutomation', :por_conta],
    ['Crm::SavedView', :por_conta],
    ['Crm::InboxSetting', :por_conta],
    ['Crm::PipelineInbox', :por_conta],
    ['Crm::InboxAgentPipeline', :por_conta],
    ['Crm::InboxAgentAccess', :por_conta],
    ['Crm::InboxAiAgent', :por_conta],
    ['Crm::PersonGoal', :por_conta],
    ['Crm::AgentBookingLink', :por_conta],
    ['Crm::AgentBookingProfile', :por_conta],
    ['Crm::BookingAccountAddress', :por_conta],
    ['Crm::MetaAdsLeadForm', :por_conta],
    ['Crm::PipelineStage', :por_conta],
    ['Crm::Pipeline', :por_conta],
    ['Crm::CalendarSyncState', :por_conta],
    ['Crm::ServiceSchedule', :por_conta],
    ['Crm::AgentAvailability', :por_conta],
    # Anúncios.
    ['Crm::MetaAdvisorAction', :por_conta],
    ['Crm::MetaAdvisorRun', :por_conta],
    ['Crm::MetaAdInsightDaily', :por_conta],
    ['Crm::MetaAdPlacementDaily', :por_conta],
    ['Crm::MetaAdFrequencyWindow', :por_conta],
    ['Crm::MetaAdLink', :por_conta],
    ['Crm::MetaAdObject', :por_conta],
    ['Crm::MetaAdsCreatedObject', :por_conta],
    ['Crm::MetaAdsConnection', :por_conta],
    ['Crm::MetaAdsPage', :por_conta],
    ['Ctwa::TrackedLinkClick', :por_conta],
    ['Ctwa::TrackedLink', :por_conta],
    # Integrações.
    ['Crm::IntegrationToken', :por_conta],
    # O token MCP tem usuário, vínculo e função técnicos próprios: o revoke! apaga os quatro.
    ['Mcp::IntegrationToken', :revogar],
    # Agentes de IA.
    ['Autonomia::Agents::ToolRun', :por_conta],
    ['Autonomia::Agents::AgentEvent', :por_conta],
    ['Autonomia::Agents::FaqSuggestion', :por_conta],
    ['Autonomia::Agents::InstructionVersion', :por_conta],
    ['Autonomia::Agents::KnowledgeEntry', :por_conta],
    ['Autonomia::Agents::Source', :por_conta],
    ['Autonomia::Agents::Specialist', :por_conta],
    ['Autonomia::Agents::Tool', :por_conta],
    ['Autonomia::Agents::BuildThread', :por_conta],
    ['Autonomia::Agents::AgentInbox', :por_conta],
    ['Autonomia::Agents::Agent', :por_conta],
    # Painel de desempenho (#2251): a leitura guardada das conversas.
    ['Autonomia::Desempenho::Procura', :por_conta], ['Autonomia::Desempenho::Leitura', :por_conta],
    ['Autonomia::Desempenho::Recomendacao', :por_conta], ['Autonomia::Desempenho::Rodada', :por_conta],
    ['Autonomia::Desempenho::Ficha', :por_conta],
    ['Autonomia::Insurance::Connection', :por_conta],
    ['Autonomia::AccountLink', :por_conta],
    # Guia da Plataforma.
    ['Autonomia::Guide::Aviso', :por_conta],
    ['Autonomia::Guide::Memoria', :por_conta],
    ['Autonomia::Guide::Execucao', :por_conta],
    ['Autonomia::Guide::Tarefa', :por_conta],
    ['Autonomia::Guide::Conversa', :por_conta],
    ['Autonomia::Guide::Vigia', :por_conta],
    # Campanhas do WhatsApp e de anúncio.
    ['WhatsappApiCampaignRecipient', :por_conta],
    ['WhatsappApiCampaign', :por_conta],
    ['WhatsappApiMessageTemplate', :por_conta],
    ['WhatsappTemplateProfile', :por_conta],
    ['CampaignRecipient', :por_conta],
    ['CampaignFreeTextDelivery', :por_conta],
    ['CampaignFreeText', :por_conta],
    ['CampaignAudienceLink', :por_conta],
    ['CampaignPause', :por_conta],
    ['CampaignReplyCode', :por_conta],
    # Público pelas conversas (#2277): pessoas e lotes saem na cascata da busca.
    ['ConversationAudienceSearch', :por_conta],
    # E-mail.
    ['ConversaCanal::EmailLido', :por_conta],
    ['ConversaCanal::EmailLidoCaixa', :por_conta],
    ['ConversaCanal::RemetenteNoSpam', :por_conta],
    ['CampaignJourneyDraft', :por_conta],
    ['EmailEvent', :por_destinatario_de_campanha],
    ['EmailCampaignRecipient', :por_campanha_de_email],
    ['EmailCampaignImport', :por_campanha_de_email],
    ['EmailCampaign', :por_conta],
    ['EmailCampaignTemplateImport', :por_conta],
    ['EmailCampaignTemplate', :por_conta],
    ['EmailTemplateImportAiQuota', :por_conta],
    ['EmailTemplate', :por_conta],
    ['EmailSenderIdentity', :por_conta],
    ['EmailSuppression', :por_conta],
    ['EmailSuppressionState', :por_conta],
    ['EmailReputationState', :por_conta],
    ['EmailProtectionMaintenanceRun', :por_conta],
    ['AccountEmailOauthApp', :por_conta],
    # Marca e etiquetas.
    ['BrandImportJob', :por_conta],
    ['BrandKit', :por_conta],
    ['Etiquetas::Nome', :por_conta],
    ['IdempotencyKey', :por_conta]
  ].freeze

  # Das ETAPAS, as que têm chave sem cascata para o que o pré-apagar do upstream apaga.
  ANTES_DO_PRE_APAGAR = ['WhatsappApiCampaignRecipient'].freeze

  # Ficam para a cascata do DELETE da conta, com o motivo.
  SAEM_COM_A_CONTA = {
    # Atribuição de IP da Webshare (#1516). Ela não sai na limpeza, mas a cascata do `destroy!` da conta a apaga antes do
    # TeardownSessionJob (que roda depois do commit, na fila low) desligar a sessão; o `release!` dele então não acha
    # nada. O que impede outra conta de pegar o IP de uma sessão ainda ligada é o WhatsappProxy::Assigner#free_ip:
    # ele descarta todo IP que alguma sessão do motor ainda usa, com ou sem atribuição no banco.
    'WhatsappProxy::Assignment' => 'sai na cascata da conta; o Assigner#free_ip não entrega IP de sessão viva no motor'
  }.freeze

  def self.tabelas
    ETAPAS.map { |modelo, _| modelo.constantize.table_name }
  end

  def self.tabelas_antes_do_pre_apagar
    ANTES_DO_PRE_APAGAR.map { |modelo| modelo.constantize.table_name }
  end

  def self.tabelas_que_saem_com_a_conta
    SAEM_COM_A_CONTA.keys.map { |modelo| modelo.constantize.table_name }
  end

  def initialize(account)
    @account = account
  end

  # Primeiro passo da exclusão: a conta para de funcionar. Suspensa, ela recusa API, widget, e-mail e webhooks dos
  # canais (como a suspensão do Super Admin), e as campanhas agendadas ou em andamento são canceladas. Assim nada novo
  # entra enquanto as tabelas saem.
  def parar_a_conta
    agora = Time.current
    # rubocop:disable Rails/SkipsModelValidations -- a conta sai mesmo que alguma validação dela não passe mais.
    account.update_columns(status: Account.statuses[:suspended], updated_at: agora)
    WhatsappApiCampaign.where(account_id: account.id, status: %i[scheduled running paused])
                       .update_all(status: WhatsappApiCampaign.statuses[:cancelled], updated_at: agora)
    EmailCampaign.where(account_id: account.id, status: %i[scheduled sending paused])
                 .update_all(status: EmailCampaign.statuses[:canceled], updated_at: agora)
    Campaign.where(account_id: account.id, campaign_type: :one_off, campaign_status: :active)
            .update_all(campaign_status: Campaign.campaign_statuses[:completed], updated_at: agora)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def antes_do_pre_apagar
    executar(ETAPAS.select { |etapa| ANTES_DO_PRE_APAGAR.include?(etapa.first) })
  end

  def perform
    executar(ETAPAS)
  end

  private

  def executar(etapas)
    etapas.each do |modelo, escopo|
      classe = modelo.constantize
      escopo == :revogar ? por_conta(classe).find_each(&:revoke!) : apagar(classe, send(escopo, classe))
    rescue StandardError => e
      # Só a conta, a etapa e a classe do erro: a mensagem do Postgres pode trazer valores da linha.
      Rails.logger.error("[ExclusaoDaConta] conta=#{account.id} etapa=#{modelo} falhou: #{e.class}")
      raise
    end
  end

  attr_reader :account

  def apagar(classe, linhas)
    linhas.in_batches(of: LOTE) do |lote|
      apagar_anexos(classe, lote) if classe.reflect_on_all_attachments.any?
      AccessToken.where(owner_type: classe.polymorphic_name, owner_id: lote.select(:id)).delete_all if classe.reflect_on_association(:access_token)
      lote.delete_all
    end
  end

  # Sem `purge_later` por anexo: ele toca o registro dono (UPDATE e callbacks) de quem está saindo. O arquivo só vai
  # para o PurgeJob quando nenhum outro anexo usa o blob (imagem reaproveitada entre modelos de e-mail, por exemplo).
  def apagar_anexos(classe, lote)
    anexos = ActiveStorage::Attachment.where(record_type: classe.polymorphic_name, record_id: lote.select(:id))
    blob_ids = anexos.pluck(:blob_id)
    anexos.delete_all
    ActiveStorage::Blob.where(id: blob_ids).where.missing(:attachments).find_each(&:purge_later)
  end

  def por_conta(classe)
    classe.unscoped.where(account_id: account.id)
  end

  def por_campanha_de_email(classe)
    classe.unscoped.where(email_campaign_id: EmailCampaign.unscoped.where(account_id: account.id).select(:id))
  end

  def por_destinatario_de_campanha(classe)
    classe.unscoped.where(recipient_id: por_campanha_de_email(EmailCampaignRecipient).select(:id))
  end
end
