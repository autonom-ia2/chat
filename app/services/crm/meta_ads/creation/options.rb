# O que a pessoa escolhe para criar (#2198, pontos 8 e 12): Páginas que concedeu (cada uma com a conta do Instagram
# ligada a ela, ou nil), números do WhatsApp da conta, fotos já usadas na conta de anúncios, limites do orçamento e só
# os destinos e lugares que a chamada real confirmou. `needs_login`: o token não pode criar; a tela pede para entrar de
# novo com o Facebook (`facebook_login`, o mesmo do GET da conexão) e não lê nada na Meta. Os posts para impulsionar
# (PR 2, #2339) são lidos por Página, quando a pessoa chega no passo do post (Crm::MetaAds::Creation::Posts). Quem pode
# criar recebe também a moeda lida na Meta (sem fallback: leitura que falha é erro, e a tela não mostra valor) e o dia
# de hoje no fuso da conta de anúncios, que vale para as datas do anúncio.
class Crm::MetaAds::Creation::Options
  KINDS = %w[ad post].freeze
  CURRENCY = Crm::MetaAds::Creation::Money::CURRENCY
  MIN_DAILY = 6
  MAX_DAILY = 500

  def initialize(account, connection)
    @account = account
    @connection = connection
    @access = Crm::MetaAds::Creation::Access.new(connection)
  end

  def payload
    can_create = @access.can_create?
    pages = can_create ? read_pages : []
    {
      needs_login: !can_create, facebook_login: Crm::MetaAds::FacebookLogin.public_payload, kinds: KINDS,
      pages: pages.map { |page| page.slice(:id, :name, :instagram) },
      whatsapp_numbers: whatsapp_numbers,
      images: can_create ? images : [], min_daily: MIN_DAILY, max_daily: MAX_DAILY, **account_facts(can_create)
    }.merge(Crm::MetaAds::Creation::Confirmed.payload)
  end

  # Posts da Página escolhida (só uma que o token alcança) e do Instagram dela. Sem poder criar: entrar de novo.
  def boost_posts(page_id)
    raise Crm::MetaAds::Creation::Error, 'cannot_create' unless @access.can_create?

    page = read_pages.find { |item| item[:id] == page_id } || raise(Crm::MetaAds::Creation::Error, 'invalid_page')
    Crm::MetaAds::Creation::Posts.new(@access.client).list(page)
  end

  # Páginas que o token alcança: [{ id:, name:, instagram: { id:, username: } | nil }]. Também usada pelo criar, para
  # conferir a Página e achar a conta do Instagram dela.
  def self.pages(client)
    result = client.pages_with_instagram
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok

    Array(result.data['data']).filter_map do |page|
      next unless page.is_a?(Hash) && page['id'].present?

      instagram = page['instagram_business_account']
      { id: page['id'].to_s, name: page['name'].to_s,
        instagram: instagram.is_a?(Hash) ? { id: instagram['id'].to_s, username: instagram['username'].to_s } : nil }
    end
  end

  # Números do WhatsApp oficial da conta, em E.164 como estão na caixa.
  def self.whatsapp_numbers(account)
    account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).order(:id).filter_map do |inbox|
      phone = inbox.channel&.phone_number
      { id: phone, name: inbox.name, phone: phone } if phone.present?
    end
  end

  private

  def read_pages
    self.class.pages(@access.client)
  end

  def whatsapp_numbers
    self.class.whatsapp_numbers(@account)
  end

  # Fotos já usadas: se a leitura falhar, a pessoa ainda sobe uma do celular.
  def images
    result = @access.client.ad_images(@connection.ad_account_id)
    return [] unless result.ok

    Array(result.data['data']).filter_map do |image|
      next unless image.is_a?(Hash) && image['hash'].present? && image['url'].present?

      { hash: image['hash'], url: image['url'], width: image['width'], height: image['height'] }
    end
  end

  # Sem poder criar, a tela pede para entrar de novo e não mostra valor nem data.
  def account_facts(can_create)
    return { currency: nil, today: nil } unless can_create

    zone = Crm::MetaAds::Creation::AccountZone.new(@connection, @access.client).zone
    { currency: Crm::MetaAds::Creation::Money.currency!(@access.client, @connection.ad_account_id), today: zone.today.iso8601 }
  end
end
