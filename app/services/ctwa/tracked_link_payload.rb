# O que a tela recebe de um link de site: sites permitidos, último aviso, código para quem cuida do site e o texto dos
# anúncios. Sem cliques, conversas nem vendas: esses saem de Ctwa::TrackedLinkCampaigns, atrás de campaign_view.
# Usado por Links e QR codes e por Anúncios › Destino (#2338).
module Ctwa::TrackedLinkPayload
  module_function

  # Quem monta várias páginas de uma vez passa `signals_blocked` já calculado (ver .blocked_ids), sem uma contagem por
  # página.
  def website(tracked_link, signals_blocked: tracked_link.signals_daily_limit_reached?)
    {
      allowed_origins: tracked_link.allowed_origins,
      last_signal_at: tracked_link.last_signal_at&.iso8601,
      # Teto diário de avisos atingido: a página está sendo recusada (429) agora.
      signals_blocked: signals_blocked,
      signal_url: "#{short_url(tracked_link)}/clicks",
      # Página pública com o código pronto para quem cuida do site (CA-1.6, #1068).
      kit_url: "#{short_url(tracked_link)}/kit",
      ad_url_params: Crm::MetaAds::UrlTags::TEXT
    }
  end

  # Mesma regra de Ctwa::TrackedLink#signals_daily_limit_reached?, numa consulta só para a lista inteira.
  def blocked_ids(tracked_link_ids)
    Ctwa::TrackedLinkClick.where(tracked_link_id: tracked_link_ids).where('created_at > ?', 24.hours.ago)
                          .group(:tracked_link_id).having('COUNT(*) >= ?', Ctwa::TrackedLink::SIGNALS_DAILY_LIMIT)
                          .pluck(:tracked_link_id).to_set
  end

  def short_url(tracked_link)
    "#{ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')}/l/#{tracked_link.code}"
  end
end
