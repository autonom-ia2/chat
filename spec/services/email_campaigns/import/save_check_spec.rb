require 'rails_helper'

# O que impede salvar em "Meus modelos" (#1099, entrega B), conferido no MJML do servidor: qualquer imagem de fora desta
# importação (bloco de imagem, fundo de seção, ícone de rede social, inclusive o padrão de mj-attributes), o trecho que
# o conversor não entendeu (até a entrega D refazê-lo) e o fundo de seção que não veio.
RSpec.describe EmailCampaigns::Import::SaveCheck, :aggregate_failures do
  let(:account) { create(:account) }
  let(:import) { EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste') }
  let(:own_url) do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: 'imagem-1.png', content_type: 'image/png')
    import.images.attach(blob)
    EmailCampaigns::Import::PublicUrl.for(blob)
  end

  around do |example|
    with_modified_env FRONTEND_URL: 'https://app.exemplo.com.br' do
      example.run
    end
  end

  def design(body, head: '')
    footer = '<mj-section css-class="footer-locked"><mj-column><mj-text><a href="{{ unsubscribe_url }}">Sair</a></mj-text></mj-column></mj-section>'
    "<mjml><mj-head>#{head}</mj-head><mj-body><mj-section><mj-column>#{body}</mj-column></mj-section>#{footer}</mj-body></mjml>"
  end

  def codes(mjml)
    described_class.call(mjml, import).pluck(:code)
  end

  it 'blocks a social icon that is not one of this import copies, and accepts the copied one' do
    social = ->(src) { %(<mj-social><mj-social-element name="facebook" href="https://f.example.com" src="#{src}">F</mj-social-element></mj-social>) }

    expect(codes(design(social.call('http://rastreador.example.com/x.png')))).to eq([:image_missing])
    expect(codes(design(social.call(own_url)))).to eq([])
  end

  it 'blocks an outside image set as a default in mj-attributes' do
    head = '<mj-attributes><mj-social-element src="https://rastreador.example.com/p.png"></mj-social-element></mj-attributes>'

    expect(codes(design('<mj-text>Oi</mj-text>', head: head))).to eq([:image_missing])
  end

  it 'blocks a part the converter left for later until it is rebuilt' do
    part = %(<mj-image src="#{EmailCampaigns::Import::Placeholders::UNRESOLVED_SRC}" title="trecho-1" alt="Promoção" ) +
           %(css-class="#{EmailCampaigns::Import::Placeholders::UNRESOLVED_CLASS}"></mj-image>)

    problems = described_class.call(design(part), import)

    expect(problems).to eq([{ code: :unresolved_parts, key: 'EMAIL_IMPORT.REPORT.UNRESOLVED_PARTS', count: 1, items: ['trecho-1'] }])
  end

  it 'blocks a section whose background image did not come' do
    marked_section = %(<mj-section css-class="#{EmailCampaigns::Import::Placeholders::MISSING_BACKGROUND_CLASS}">)
    marked = design('<mj-text>Oi</mj-text>').sub('<mj-section>', marked_section)

    expect(codes(marked)).to eq([:image_missing])
  end

  # Invariante: todo aviso que bloqueia no relatório tem de ser visto por esta conferência no MJML.
  it 'sees every image the converter reported as missing, and lets a social icon fall back to its default' do
    social = '<mj-social><mj-social-element name="facebook" href="https://f.example.com" src="icone.png">F</mj-social-element></mj-social>'
    mjml = '<mjml><mj-body><mj-section background-url="fundo.png"><mj-column><mj-text>Oi</mj-text></mj-column></mj-section>' \
           "<mj-section><mj-column>#{social}</mj-column></mj-section></mj-body></mjml>"

    result = EmailCampaigns::Import::Engine.call(mjml, source_kind: 'paste')

    expect(result.report.count(:image_missing)).to eq(1)
    expect(result.report.count(:social_icon_default)).to eq(1)
    expect(codes(result.mjml)).to eq([:image_missing])
    expect(result.mjml).not_to include('icone.png')
  end

  it 'lists the social icons of an MJML model for the image step to copy' do
    social = '<mj-social><mj-social-element name="facebook" href="https://f.example.com" src="http://rastreador.example.com/x.png">F' \
             '</mj-social-element></mj-social>'
    mjml = "<mjml><mj-body><mj-section><mj-column>#{social}</mj-column></mj-section></mj-body></mjml>"

    result = EmailCampaigns::Import::Engine.call(mjml, source_kind: 'paste')

    expect(result.report.images.pluck(:src)).to eq(['http://rastreador.example.com/x.png'])
  end
end
