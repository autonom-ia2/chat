# De onde sai o painel de Anúncios (#1960): da conexão com conta de anúncios (painel completo, com gasto) ou, com
# Anúncios sem login ligado e sem essa conexão, do que o WhatsApp contou (fonte nil, Crm::MetaAds::SemLogin).
# Espera `current_connection` no controller.
module Crm::MetaAdsPanelSource
  extend ActiveSupport::Concern

  private

  def whatsapp_panel?
    @whatsapp_panel = ::Crm::MetaAds::SemLogin.whatsapp_panel?(Current.account) unless defined?(@whatsapp_panel)
    @whatsapp_panel
  end

  def panel_ready?
    whatsapp_panel? || current_connection&.ad_account_id.present?
  end

  def panel_source
    whatsapp_panel? ? nil : current_connection
  end

  # O mesmo painel da conexão, sem gasto, com o tempo de resposta do período (das conversas que o WhatsApp contou).
  def whatsapp_panel_payload
    report = ::Crm::MetaAds::Panel::Report.new(nil, period: panel_period, account: Current.account)
    report.payload.merge(response_time: whatsapp_response_time(report))
  end

  def whatsapp_response_time(report)
    return if report.cohort.conversation_ads.empty?

    ::Crm::MetaAds::Panel::ResponseTime.new(account_id: report.account_id, range: report.range, starts: report.cohort.starts)
                                       .payload.merge(days: report.days)
  end

  # O período pedido (#2011): `period` pelo nome; o `days` antigo (7 ou 30) segue valendo para quem ainda pede assim.
  def panel_period
    ::Crm::MetaAds::Panel::Period.key_for(period: params[:period], days: params[:days])
  end

  # Período, conversas que a pessoa já vê (#1794) e a conta, comuns ao anúncio por dentro e às listas.
  def panel_scope
    { period: panel_period, visible: ::Crm::MetaAds::VisibleConversations.current, account: Current.account }
  end
end
