# Público "já enviado" (#2775): a trava que impede mudar quem está num Público depois que uma campanha ligada a ele
# começou a sair. A tela (a marca "já enviada" e o "Criar uma cópia para editar") e o servidor
# (CampaignJourney::AudienceMembership) leem esta mesma regra.
#
# Parte dos vínculos do Público (campaign_import.campaign_audience_links), um por campanha, de três tipos:
# - EmailCampaign: trava quando algum destinatário já tem sent_at, ou com o status sending, paused ou sent. Rascunho e
#   agendada não travam: a lista de e-mail segue o Público até o 1º envio (CampaignJourney::EmailAudienceGate, que esta
#   regra só lê). Exceção: a campanha "aberta" (#2717, coluna email_campaigns.aberta) recebe quem entra depois e nunca
#   trava; enquanto a coluna não existe, nenhuma campanha é aberta.
# - WhatsappApiCampaign: trava com qualquer status diferente de scheduled (running, paused, completed...).
# - Campaign (envio único do Chatwoot, WhatsApp ou SMS): trava com campaign_status processing ou completed. "active" é a
#   agendada que ainda não saiu, e não trava.
# Vínculo sem campanha (campanha apagada) não trava; tipo desconhecido trava, pelo lado seguro.
#
# Diferente de CampaignImports::AudienceUsage, que diz quais campanhas ainda dependem do Público (para não apagar nem
# desligar canal): aqui a pergunta é se alguém já recebeu por ele.
module CampaignJourney::AudienceUsage
  EMAIL_LOCKING_STATUSES = %w[sending paused sent].freeze
  CAMPAIGN_LOCKING_STATUSES = %w[processing completed].freeze

  module_function

  def locked?(campaign_import)
    locked_ids([campaign_import]).include?(campaign_import.id)
  end

  # Os ids dos Públicos travados entre os dados, numa consulta só pelos vínculos (a lista "Suas listas").
  def locked_ids(campaign_imports)
    ids = campaign_imports.map(&:id)
    return Set.new if ids.empty?

    CampaignAudienceLink.where(campaign_import_id: ids).includes(:campaign)
                        .select { |link| campaign_locked?(link.campaign) }
                        .to_set(&:campaign_import_id)
  end

  def campaign_locked?(campaign)
    case campaign
    when nil then false
    when EmailCampaign then email_locked?(campaign)
    when WhatsappApiCampaign then !campaign.scheduled?
    when Campaign then CAMPAIGN_LOCKING_STATUSES.include?(campaign.campaign_status)
    else true
    end
  end

  def email_locked?(campaign)
    return false if open_email_campaign?(campaign)

    EMAIL_LOCKING_STATUSES.include?(campaign.status) || campaign.email_campaign_recipients.where.not(sent_at: nil).exists?
  end

  # #2717: a campanha de e-mail "aberta" segue recebendo quem entra no Público, então mudar o Público não muda o que já
  # saiu. Lido só quando a coluna existe (o #2717 pode chegar à main depois desta regra).
  def open_email_campaign?(campaign)
    campaign.has_attribute?(:aberta) && campaign[:aberta] == true
  end
end
