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
# Corrida aceita: começar uma campanha não tranca a linha do Público, então uma mudança no mesmo segundo do disparo pode
# entrar ou não naquele envio. Não causa dano: o envio confere de novo, contato por contato, quem pode receber (a régua
# do envio vale outra vez), e a mudança seguinte já encontra o Público travado.
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

  # Os ids dos Públicos travados entre os dados (a lista "Suas listas"): uma consulta pelos vínculos e uma só pelas
  # campanhas de e-mail que já têm destinatário enviado, sem N+1.
  def locked_ids(campaign_imports)
    ids = campaign_imports.map(&:id)
    return Set.new if ids.empty?

    links = CampaignAudienceLink.where(campaign_import_id: ids).includes(:campaign).to_a
    sent_email_ids = email_ids_with_sent_recipient(links.filter_map(&:campaign).grep(EmailCampaign).map(&:id))
    links.select { |link| campaign_locked?(link.campaign, sent_email_ids: sent_email_ids) }.to_set(&:campaign_import_id)
  end

  # sent_email_ids: os ids das campanhas de e-mail com algum destinatário enviado, quando já lidos de uma vez; sem ele,
  # a campanha de e-mail é lida sozinha.
  def campaign_locked?(campaign, sent_email_ids: nil)
    case campaign
    when nil then false
    when EmailCampaign then email_locked?(campaign, sent_email_ids)
    when WhatsappApiCampaign then !campaign.scheduled?
    when Campaign then CAMPAIGN_LOCKING_STATUSES.include?(campaign.campaign_status)
    else true
    end
  end

  def email_ids_with_sent_recipient(campaign_ids)
    return Set.new if campaign_ids.empty?

    EmailCampaignRecipient.where(email_campaign_id: campaign_ids).where.not(sent_at: nil).distinct.pluck(:email_campaign_id).to_set
  end

  def email_locked?(campaign, sent_email_ids = nil)
    return false if open_email_campaign?(campaign)
    return true if EMAIL_LOCKING_STATUSES.include?(campaign.status)

    (sent_email_ids || email_ids_with_sent_recipient([campaign.id])).include?(campaign.id)
  end

  # #2717: a campanha de e-mail "aberta" segue recebendo quem entra no Público, então mudar o Público não muda o que já
  # saiu. Lido só quando a coluna existe (o #2717 pode chegar à main depois desta regra).
  def open_email_campaign?(campaign)
    campaign.has_attribute?(:aberta) && campaign[:aberta] == true
  end
end
