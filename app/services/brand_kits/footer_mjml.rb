# Rodapé travado de um e-mail com identidade (#1076). É SEMPRE o rodapé canônico (lockedFooter.json,
# EmailCampaigns::LockedFooter, #1081 — texto legal, cores e o único link de descadastro); o kit só
# preenche a linha de identidade do topo — empresa · endereço · site — e, quando há, uma linha de redes
# como links de texto (sem ícone de outro servidor). Todo valor do kit é escapado.
class BrandKits::FooterMjml
  SEPARATOR = ' · '.freeze
  # Mesma cor de link do rodapé canônico (#4b5563 sobre #f4f4f4, contraste AA).
  LINK_STYLE = 'color:#4b5563;text-decoration:underline;'.freeze
  NETWORK_LABELS = {
    'facebook' => 'Facebook', 'instagram' => 'Instagram', 'linkedin' => 'LinkedIn', 'youtube' => 'YouTube',
    'tiktok' => 'TikTok', 'x' => 'X', 'whatsapp' => 'WhatsApp'
  }.freeze

  # payload: { footer: { company_name, address, website }, social_links: [{ network, url }] }
  def initialize(payload)
    @footer = payload[:footer] || {}
    @social_links = payload[:social_links] || []
  end

  def to_s
    lines = [identity_line, social_line].compact
    return EmailCampaigns::LockedFooter::MJML if lines.empty?

    EmailCampaigns::LockedFooter.with_first_line(lines.join('<br/>'))
  end

  private

  def identity_line
    parts = [@footer[:company_name], @footer[:address]].compact.map { |value| escape(value) }
    website = @footer[:website]
    parts << link(website, host(website)) if website.present?
    parts.join(SEPARATOR).presence
  end

  def social_line
    links = @social_links.filter_map do |item|
      label = NETWORK_LABELS[item[:network]]
      link(item[:url], label) if label && item[:url].present?
    end
    links.join(SEPARATOR).presence
  end

  def link(url, label)
    %(<a href="#{escape(url)}" style="#{LINK_STYLE}">#{escape(label)}</a>)
  end

  def host(url)
    URI.parse(url).host.to_s.delete_prefix('www.').presence || url
  rescue URI::Error
    url
  end

  def escape(value)
    ERB::Util.html_escape(value.to_s)
  end
end
