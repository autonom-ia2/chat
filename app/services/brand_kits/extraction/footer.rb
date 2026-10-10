# Dados do rodapé do e-mail (#1076): empresa, endereço, telefone e site. JSON-LD primeiro (dado que a
# própria marca publicou), depois <address> e o primeiro link tel: da página.
class BrandKits::Extraction::Footer
  ADDRESS_MAX = BrandKits::Appearance::FOOTER_LIMITS['address']
  PHONE_MAX = BrandKits::Appearance::FOOTER_LIMITS['phone']

  Field = Struct.new(:value, :source, :confidence)

  def initialize(document, json_ld:, company_name:, page_uri:)
    @document = document
    @json_ld = json_ld
    @company_name = company_name
    @page_uri = page_uri
  end

  def perform
    {
      'company_name' => company_name,
      'address' => address,
      'phone' => phone,
      'website' => website
    }
  end

  private

  def company_name
    return Field.new(@json_ld.name, 'json_ld', 'high') if @json_ld.name
    return Field.new(@company_name, 'site_name', 'medium') if @company_name

    Field.new(nil, nil, nil)
  end

  def address
    return Field.new(@json_ld.address.truncate(ADDRESS_MAX), 'json_ld', 'high') if @json_ld.address

    text = @document.at_css('address')&.text.to_s.squish.presence
    text ? Field.new(text.truncate(ADDRESS_MAX), 'address_tag', 'medium') : Field.new(nil, nil, nil)
  end

  def phone
    return Field.new(@json_ld.telephone.truncate(PHONE_MAX), 'json_ld', 'high') if @json_ld.telephone

    link = @document.at_css('a[href^="tel:"]')
    return Field.new(nil, nil, nil) if link.nil?

    label = link.text.to_s.squish
    number = label.each_char.any? { |char| char.between?('0', '9') } ? label : link['href'].delete_prefix('tel:')
    Field.new(number.truncate(PHONE_MAX).presence, 'tel_link', 'medium')
  end

  def website
    declared = BrandKits::WebAddress.parse(@json_ld.url)
    return Field.new(BrandKits::WebAddress.origin(declared), 'json_ld', 'high') if declared

    Field.new(BrandKits::WebAddress.origin(@page_uri), 'page_url', 'high')
  end
end
