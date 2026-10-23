# Exclusão da conta (#2133): apaga o que o fork guarda da conta antes do `account.destroy!` do DeleteObjectJob.
#
# As associações da conta são `dependent: :destroy_async`, que só enfileiram a exclusão depois do commit. As tabelas do
# fork apontam para a conta (e umas para as outras) com chave estrangeira sem cascata, então o DELETE da conta esbarrava
# nelas e o job falhava com a conta inteira no banco. Aqui elas saem antes, em lote e na ordem das chaves: cada tabela
# vem antes das que ela referencia. Saem também as tabelas da conta sem chave estrangeira (uso de IA, conversões da Meta,
# horários de atendimento), que ninguém mais apagaria. O spec `exclusao_da_conta_spec` lê as chaves do banco e falha
# quando aparece tabela nova que barraria a exclusão, ou tabela com account_id que ninguém apaga.
#
# `delete_all` não roda callbacks. Dos efeitos deles, ficam os que importam:
# - anexos (Active Storage): as linhas saem junto do lote e os arquivos vão para o PurgeJob;
# - tokens de integração: o `access_token` (o bearer) sai junto, para não sobrar credencial de dono apagado.
# A conexão do WhatsApp Híbrido não está aqui: ela sai com a caixa (`Inbox has_one ..., dependent: :destroy`), que o job
# apaga antes, e o callback dela desliga a sessão no WAHA.
# Reunião marcada no Google ou na Microsoft não é cancelada: a conta está saindo, as caixas (e o acesso ao calendário)
# já foram apagadas antes daqui, e o evento continua no calendário de quem a marcou.
class Autonomia::ExclusaoDaConta
  LOTE = 5_000

  # [modelo, como achar as linhas da conta]. A ordem é a das chaves estrangeiras: filho antes do pai.
  ETAPAS = [
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
    ['Crm::Card', :por_conta],
    ['Crm::StageAutomationStep', :por_conta],
    ['Crm::StageAutomation', :por_conta],
    ['Crm::SavedView', :por_conta],
    ['Crm::InboxSetting', :por_conta],
    ['Crm::PipelineInbox', :por_conta],
    ['Crm::AgentBookingLink', :por_conta],
    ['Crm::AgentBookingProfile', :por_conta],
    ['Crm::PipelineStage', :por_conta],
    ['Crm::Pipeline', :por_conta],
    ['Crm::CalendarSyncState', :por_conta],
    ['Crm::ServiceSchedule', :por_conta],
    ['Crm::AgentAvailability', :por_conta],
    ['Crm::MetaAdObject', :por_conta],
    ['Crm::IntegrationToken', :por_conta],
    ['Mcp::IntegrationToken', :por_conta],
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
    ['Autonomia::Insurance::Connection', :por_conta],
    ['WhatsappApiCampaignRecipient', :por_conta],
    ['WhatsappApiCampaign', :por_conta],
    ['WhatsappApiMessageTemplate', :por_conta],
    ['EmailEvent', :por_destinatario_de_campanha],
    ['EmailCampaignRecipient', :por_campanha_de_email],
    ['EmailCampaignImport', :por_campanha_de_email],
    ['EmailCampaign', :por_conta],
    ['EmailCampaignTemplate', :por_conta],
    ['EmailTemplate', :por_conta],
    ['EmailSenderIdentity', :por_conta],
    ['EmailSuppression', :por_conta],
    ['AccountEmailOauthApp', :por_conta],
    ['IdempotencyKey', :por_conta]
  ].freeze

  def self.tabelas
    ETAPAS.map { |modelo, _| modelo.constantize.table_name }
  end

  def initialize(account)
    @account = account
  end

  def perform
    ETAPAS.each do |modelo, escopo|
      classe = modelo.constantize
      apagar(classe, send(escopo, classe))
    end
  end

  private

  attr_reader :account

  def apagar(classe, linhas)
    linhas.in_batches(of: LOTE) do |lote|
      apagar_anexos(classe, lote) if classe.reflect_on_all_attachments.any?
      AccessToken.where(owner_type: classe.polymorphic_name, owner_id: lote.select(:id)).delete_all if classe.reflect_on_association(:access_token)
      lote.delete_all
    end
  end

  # Sem `purge_later` por anexo: ele toca o registro dono (UPDATE e callbacks) de quem está saindo.
  def apagar_anexos(classe, lote)
    anexos = ActiveStorage::Attachment.where(record_type: classe.polymorphic_name, record_id: lote.select(:id))
    blob_ids = anexos.pluck(:blob_id)
    anexos.delete_all
    ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge_later)
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
