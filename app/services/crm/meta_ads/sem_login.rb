# Anúncios sem login (#1960, degrau 0): a página de anúncios abre pronta com o que o WhatsApp já conta — de qual
# anúncio (clique para o WhatsApp) veio cada conversa e o que virou no CRM —, sem a conexão com o Facebook, que só
# lê dados de clientes depois da aprovação da Meta. Vale para conta com a flag `anuncios_sem_login`, com WhatsApp
# oficial (só ele recebe de qual anúncio veio a pessoa) e sem conexão de anúncios nenhuma. Quem já tem conexão
# (ativa, caída ou no meio da escolha da conta) segue no caminho antigo, que leva ao painel com gasto e a "Conectar
# de novo"; quem não tem WhatsApp oficial também segue nele, sem mudança.
module Crm::MetaAds::SemLogin
  module_function

  FLAG = 'anuncios_sem_login'.freeze
  # Janela do "teve clique de anúncio recente" da tela vazia.
  RECENT_WINDOW = 90.days

  def enabled?(account_or_id)
    account = account_or_id.is_a?(Account) ? account_or_id : Account.find_by(id: account_or_id)
    account.present? && account.feature_enabled?(FLAG)
  end

  def whatsapp_panel?(account)
    enabled?(account) && !Crm::MetaAdsConnection.exists?(account_id: account.id) &&
      account.inboxes.exists?(channel_type: 'Channel::Whatsapp')
  end

  # O que a tela vazia precisa saber: quais WhatsApp oficiais estão prontos e se já chegou alguém de anúncio. As
  # caixas (nome e número) são só as que a pessoa acessa; o administrador vê todas.
  def payload(account, account_user)
    return { enabled: false } unless whatsapp_panel?(account)

    { enabled: true, official_inboxes: official_inboxes(account, account_user), recent_ad_touch: recent_ad_touch?(account) }
  end

  def official_inboxes(account, account_user)
    caixas = account.inboxes.where(channel_type: 'Channel::Whatsapp')
    caixas = caixas.where(id: account_user&.user&.inboxes&.select(:id) || Inbox.none) unless account_user&.administrator?
    caixas.includes(:channel).order(:id).map do |inbox|
      { id: inbox.id, name: inbox.name, phone: inbox.channel.phone_number }
    end
  end

  # A mesma regra da coorte do painel (clique para o WhatsApp ou site com sinal da Meta), nos últimos RECENT_WINDOW.
  def recent_ad_touch?(account)
    Crm::MetaAds::Panel::WhatsappCohort.new(account.id, RECENT_WINDOW.ago..Time.current).any?
  end
end
