# Anúncios sem login (#1960, degrau 0): a página de anúncios abre pronta com o que o WhatsApp já conta — de qual
# anúncio (clique para o WhatsApp) veio cada conversa e o que virou no CRM —, sem a conexão com o Facebook, que só
# lê dados de clientes depois da aprovação da Meta. Vale para conta com a flag `anuncios_sem_login`, com WhatsApp
# oficial (só ele recebe de qual anúncio veio a pessoa) e sem conexão de anúncios que dê painel com gasto. Quem não
# tem WhatsApp oficial segue no caminho antigo, sem mudança.
#
# Conectar a partir daqui (#2054): conexão no meio do caminho (entrou com o Facebook e ainda não escolheu a conta) ou
# caída (a Meta parou de responder) não tira a pessoa desta página: o painel do WhatsApp continua, com
# `connection_state` ('choosing' ou 'broken') para a tela oferecer "Continuar" ou "Conectar de novo". Só a conexão
# ativa com conta de anúncios leva ao painel com gasto.
module Crm::MetaAds::SemLogin
  module_function

  FLAG = 'anuncios_sem_login'.freeze
  def enabled?(account_or_id)
    account = account_or_id.is_a?(Account) ? account_or_id : Account.find_by(id: account_or_id)
    account.present? && account.feature_enabled?(FLAG)
  end

  def whatsapp_panel?(account)
    enabled?(account) && !spend_panel?(account) && account.inboxes.exists?(channel_type: 'Channel::Whatsapp')
  end

  def spend_panel?(account)
    Crm::MetaAdsConnection.where(account_id: account.id, status: 'active').where.not(ad_account_id: nil).exists?
  end

  # nil sem conexão; 'choosing' sem conta de anúncios escolhida; 'broken' com a conexão caída.
  def connection_state(account)
    connection = Crm::MetaAdsConnection.find_by(account_id: account.id)
    return if connection.blank?

    connection.ad_account_id.blank? ? 'choosing' : 'broken'
  end

  # O que a tela vazia precisa saber: quais WhatsApp oficiais estão prontos e se já chegou alguém de anúncio. As
  # caixas (nome e número) são só as que a pessoa acessa; quem configura os anúncios da conta (administrador ou
  # `meta_ads_manage`, #2070) vê todas, como já vê nas origens do resumo no WhatsApp.
  def payload(account, account_user)
    return { enabled: false } unless whatsapp_panel?(account)

    { enabled: true, official_inboxes: official_inboxes(account, account_user), ad_touch: ad_touch?(account),
      connection_state: connection_state(account), connection_mode: Crm::MetaAdsConnection.where(account_id: account.id).pick(:mode) }
  end

  def official_inboxes(account, account_user)
    caixas = account.inboxes.where(channel_type: 'Channel::Whatsapp')
    caixas = caixas.where(id: account_user&.user&.inboxes&.select(:id) || Inbox.none) unless account_user&.permission_granted?('meta_ads_manage')
    caixas.includes(:channel).order(:id).map do |inbox|
      { id: inbox.id, name: inbox.name, phone: inbox.channel.phone_number }
    end
  end

  # Já chegou alguém de anúncio, em qualquer época (#2011)? A mesma regra da coorte do painel (clique para o WhatsApp
  # ou site com sinal da Meta), no mesmo alcance do "Desde o início": quem já anunciou vê o painel, com o histórico,
  # mesmo depois de meses parado.
  def ad_touch?(account)
    Crm::MetaAds::Panel::WhatsappCohort.new(account.id, Crm::MetaAds::Panel::Period::MAX_MONTHS.months.ago..Time.current).any?
  end
end
