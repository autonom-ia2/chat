require 'rails_helper'

# A forma que a Meta exige antes de criar ou alterar um modelo (#1380).
RSpec.describe Whatsapp::Templates::SubmitFormat do
  def template(category, *components)
    { 'category' => category, 'components' => [{ 'type' => 'BODY', 'text' => 'Oi.' }, *components] }
  end

  def buttons(*list)
    { 'type' => 'BUTTONS', 'buttons' => list }
  end

  def card(header: true, text: 'Novidade', button: { 'type' => 'URL', 'text' => 'Ver', 'url' => 'https://h.com' })
    parts = [{ 'type' => 'BODY', 'text' => text }]
    parts.unshift({ 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['h'] } }) if header
    parts << buttons(button) if button
    { 'components' => parts }
  end

  # O que a Nova campanha grava para cada formato (PonteFormatoDaCampanha → Whatsapp::Templates::SendParams).
  def what_the_campaign_fills(template)
    components = Array(template['components'])
    { 'buttons' => campaign_buttons(component_named(components, 'BUTTONS')),
      'limited_time_offer' => { 'expiration_time_ms' => 1.day.from_now.to_i * 1000 },
      'carousel' => { 'cards' => Array(component_named(components, 'CAROUSEL')&.dig('cards')).map { |card| campaign_card(card) } } }
      .merge(campaign_products(template))
  end

  # #1418: o modelo de produtos leva o mínimo de produtos que a Meta aceita (1; 2 no carrossel).
  def campaign_products(template)
    kind = Whatsapp::Templates::ProductParams.kind(template)
    return {} unless kind

    ids = Array.new(Whatsapp::Templates::ProductParams::LIMITS[kind].min) { |index| "sku-#{index}" }
    { 'products' => { 'retailer_ids' => ids } }
  end

  def component_named(components, type)
    components.find { |item| item['type'] == type }
  end

  def campaign_buttons(component)
    Array(component&.dig('buttons')).map do |button|
      next { 'type' => 'copy_code', 'parameter' => Array(button['example']).first.to_s } if button['type'] == 'COPY_CODE'

      button['type'] == 'CATALOG' ? { 'type' => 'catalog' } : { 'type' => 'static' }
    end
  end

  def campaign_card(card)
    buttons = Array(component_named(Array(card['components']), 'BUTTONS')&.dig('buttons'))
    { 'header' => { 'media_stored' => true }, 'buttons' => buttons.map { { 'type' => 'url', 'parameter' => 'x' } } }
  end

  describe 'Prontos da galeria (spec/fixtures/whatsapp_templates/prontos.json, gerado pelo vitest da tela)' do
    prontos = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_templates/prontos.json').read)

    it 'cobre todos os objetivos e formatos, nos dois idiomas' do
      expect(prontos.map { |pronto| pronto['idioma'] }.uniq).to contain_exactly('en', 'pt_BR')
      expect(prontos.map { |pronto| pronto['chave'] }).to include('cobranca', 'oferta', 'carrossel', 'codigo')
    end

    prontos.each do |pronto|
      label = "#{pronto['idioma']}/#{pronto['chave']}"

      it "#{label} passa na forma que a Meta exige" do
        expect(described_class.problems(pronto['corpo'])).to eq([])
      end

      # #1334: com o que a campanha pede na tela (cupom, validade, arquivo de cada cartão), o formato vai.
      it "#{label}: a campanha envia exatamente o que a tela promete" do
        sendable = Whatsapp::Templates::SendableFormat.check(pronto['corpo'], recorded: what_the_campaign_fills(pronto['corpo']))
        expect(sendable.sendable?).to eq(pronto['pode_ir_em_campanha']), "motivo: #{sendable.reason_code.inspect}"
        expect(sendable.sendable?).to be(true) if pronto['origem'] == 'objetivo'
      end

      next unless pronto['corpo']['category'] == 'UTILITY'

      it "#{label}: aviso de serviço sem nada que só existe em divulgação" do
        components = pronto['corpo']['components']
        expect(described_class.marketing_only?(components)).to be(false)
      end
    end
  end

  it 'aceita um aviso simples com botões completos' do
    template = template('UTILITY', buttons({ 'type' => 'QUICK_REPLY', 'text' => 'Confirmo' },
                                           { 'type' => 'URL', 'text' => 'Ver', 'url' => 'https://h.com' },
                                           { 'type' => 'PHONE_NUMBER', 'text' => 'Ligar', 'phone_number' => '+551140000000' }))
    expect(described_class.problems(template)).to eq([])
  end

  it 'recusa o pronto antigo do boleto: COPY_CODE sem exemplo num aviso' do
    template = template('UTILITY', buttons({ 'type' => 'COPY_CODE', 'example' => nil }))
    expect(described_class.problems(template)).to eq(%w[marketing_only copy_code_example])
  end

  it 'aceita COPY_CODE com código válido em divulgação (string ou lista, como a Meta devolve)' do
    expect(described_class.problems(template('MARKETING', buttons({ 'type' => 'COPY_CODE', 'example' => 'PROMO10' })))).to eq([])
    expect(described_class.problems(template('MARKETING', buttons({ 'type' => 'COPY_CODE', 'example' => ['PROMO10'] })))).to eq([])
  end

  it 'código de exemplo: de 1 a 15 letras e números' do
    expect(%w[A PROMO10 ABCDEFGHIJ12345].map { |code| described_class.valid_code?(code) }).to all(be(true))
    expect(['', nil, 'ABCDEFGHIJ123456', '2345 6789', 'PROMO-10', 'CAFÉ'].map { |code| described_class.valid_code?(code) })
      .to all(be(false))
  end

  it 'acusa botão sem texto, site sem endereço e ligar sem número' do
    template = template('UTILITY', buttons({ 'type' => 'QUICK_REPLY', 'text' => ' ' }, { 'type' => 'URL', 'text' => 'Ver' },
                                           { 'type' => 'PHONE_NUMBER', 'text' => 'Ligar', 'phone_number' => '' }))
    expect(described_class.problems(template)).to eq(%w[button_text_missing url_missing phone_missing])
  end

  it 'texto de botão até 25 letras' do
    ok = template('UTILITY', buttons({ 'type' => 'QUICK_REPLY', 'text' => 'x' * 25 }))
    long = template('UTILITY', buttons({ 'type' => 'QUICK_REPLY', 'text' => 'Quero falar com um atendente agora' }))
    expect(described_class.problems(ok)).to eq([])
    expect(described_class.problems(long)).to eq(['button_text_long'])
  end

  it 'respostas rápidas ficam juntas, antes ou depois dos outros botões' do
    quick = { 'type' => 'QUICK_REPLY', 'text' => 'Sim' }
    url = { 'type' => 'URL', 'text' => 'Site', 'url' => 'https://x.com' }
    expect(described_class.problems(template('UTILITY', buttons(quick, quick, url)))).to eq([])
    expect(described_class.problems(template('UTILITY', buttons(url, quick, quick)))).to eq([])
    expect(described_class.problems(template('UTILITY', buttons(quick, url, quick)))).to eq(['button_order'])
    expect(described_class.problems(template('UTILITY', buttons(url, quick, url)))).to eq(['button_order'])
  end

  it 'site com final variável precisa do exemplo desse final' do
    variable = { 'type' => 'URL', 'text' => 'Responder', 'url' => 'https://h.com/survey/{{1}}' }
    expect(described_class.problems(template('UTILITY', buttons(variable)))).to eq(['url_example'])
    expect(described_class.problems(template('UTILITY', buttons(variable.merge('example' => ['12345']))))).to eq([])
  end

  it 'topo de foto, vídeo ou documento precisa do handle do arquivo (vazio também não vale)' do
    header = ->(handle) { { 'type' => 'HEADER', 'format' => 'DOCUMENT', 'example' => { 'header_handle' => handle } } }
    expect(described_class.problems(template('UTILITY', header.call(['4::h'])))).to eq([])
    expect(described_class.problems(template('UTILITY', header.call([''])))).to eq(['media_required'])
    expect(described_class.problems(template('UTILITY', { 'type' => 'HEADER', 'format' => 'IMAGE' }))).to eq(['media_required'])
    expect(described_class.problems(template('UTILITY', { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Oi' }))).to eq([])
  end

  it 'chaves duplas só no corpo: rodapé, botão e título da oferta recusam' do
    footer = template('UTILITY', { 'type' => 'FOOTER', 'text' => 'até {{1}}' })
    button = template('UTILITY', buttons({ 'type' => 'QUICK_REPLY', 'text' => 'Sim {{' }))
    expect(described_class.problems(footer)).to eq(['stray_braces'])
    expect(described_class.problems(button)).to eq(['stray_braces'])
    expect(described_class.problems(template('UTILITY', { 'type' => 'FOOTER', 'text' => 'Sua Empresa' }))).to eq([])
  end

  it 'mede o texto do botão como vai, com espaços' do
    expect(described_class.problems(template('UTILITY', buttons({ 'type' => 'QUICK_REPLY', 'text' => " #{'x' * 25}" }))))
      .to eq(['button_text_long'])
  end

  it 'site com endereço completo (só ASCII, sem espaço, com //)' do
    site = ->(url) { template('UTILITY', buttons({ 'type' => 'URL', 'text' => 'Ver', 'url' => url })) }
    expect(described_class.problems(site.call('https://sualoja.com.br/x'))).to eq([])
    expect(described_class.problems(site.call('https://h.com/r/{{1}}').tap { |t| t['components'][1]['buttons'][0]['example'] = ['1'] }))
      .to eq([])
    expect(described_class.problems(site.call('hub2you'))).to eq(['url_invalid'])
    expect(described_class.problems(site.call('https://café.com.br'))).to eq(['url_invalid'])
    expect(described_class.problems(site.call('https:x.com'))).to eq(['url_invalid'])
  end

  it 'ligar com o código do país' do
    ligar = ->(phone) { template('UTILITY', buttons({ 'type' => 'PHONE_NUMBER', 'text' => 'Ligar', 'phone_number' => phone })) }
    expect(described_class.problems(ligar.call('+551140000000'))).to eq([])
    expect(described_class.problems(ligar.call('abc'))).to eq(['phone_invalid'])
    expect(described_class.problems(ligar.call('11999999999'))).to eq(['phone_invalid'])
  end

  it 'código de verificação (OTP) não conta como divulgação' do
    template = { 'category' => 'AUTHENTICATION', 'components' => [{ 'type' => 'BODY' }, buttons({ 'type' => 'OTP', 'otp_type' => 'COPY_CODE' })] }
    expect(described_class.problems(template)).to eq([])
  end

  describe 'carrossel' do
    it 'aceita de 2 a 10 cartões completos, só em divulgação' do
      carousel = { 'type' => 'CAROUSEL', 'cards' => [card, card] }
      expect(described_class.problems(template('MARKETING', carousel))).to eq([])
      expect(described_class.problems(template('UTILITY', carousel))).to eq(['marketing_only'])
    end

    it 'recusa foto num cartão e vídeo no outro' do
      video = card.tap { |c| c['components'][0]['format'] = 'VIDEO' }
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [card, video] }))).to eq(['carousel_media'])
    end

    it 'recusa quantidade errada e cartão incompleto' do
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [card] }))).to eq(['carousel_cards'])
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [card, card(header: false)] })))
        .to eq(['carousel_card'])
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [card, card(text: '')] })))
        .to eq(['carousel_card'])
      no_url = card(button: { 'type' => 'URL', 'text' => 'Ver', 'url' => '' })
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [card, no_url] }))).to eq(['url_missing'])
    end

    # #1418: o cartão de produto não tem foto nossa nem texto: o topo PRODUCT vem do catálogo e o botão é o "Ver" (SPM).
    it 'aceita o carrossel de produtos: topo PRODUCT e um botão em cada cartão' do
      produto = { 'components' => [{ 'type' => 'HEADER', 'format' => 'PRODUCT' }, buttons({ 'type' => 'SPM', 'text' => 'Ver' })] }
      sem_botao = { 'components' => [{ 'type' => 'HEADER', 'format' => 'PRODUCT' }] }
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [produto, produto] }))).to eq([])
      expect(described_class.problems(template('UTILITY', { 'type' => 'CAROUSEL', 'cards' => [produto, produto] }))).to eq(['marketing_only'])
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [produto, sem_botao] })))
        .to eq(['carousel_card'])
    end
  end

  describe 'oferta por tempo limitado' do
    def offer(text: 'Só hoje', expiration: true)
      { 'type' => 'LIMITED_TIME_OFFER', 'limited_time_offer' => { 'text' => text, 'has_expiration' => expiration } }
    end
    let(:url) { { 'type' => 'URL', 'text' => 'Ver oferta', 'url' => 'https://h.com' } }
    let(:coupon) { { 'type' => 'COPY_CODE', 'example' => 'HUB30' } }

    it 'aceita título, cupom e link' do
      expect(described_class.problems(template('MARKETING', offer, buttons(coupon, url)))).to eq([])
    end

    it 'recusa título longo, falta de link e contagem sem cupom' do
      expect(described_class.problems(template('MARKETING', offer(text: 'x' * 17), buttons(coupon, url)))).to eq(['offer_title'])
      expect(described_class.problems(template('MARKETING', offer, buttons(coupon)))).to eq(['offer_buttons'])
      expect(described_class.problems(template('MARKETING', offer, buttons(url)))).to eq(['offer_buttons'])
      expect(described_class.problems(template('MARKETING', offer(expiration: false), buttons(url)))).to eq([])
    end
  end

  # #1394: a Meta não aceita trocar a categoria de um modelo que já existe; o produto trata como não editável sempre.
  describe '.edit_problems' do
    let(:current) { { 'category' => 'MARKETING', 'status' => 'REJECTED' } }

    it 'recusa a troca de categoria na edição, com qualquer situação do modelo' do
      expect(described_class.edit_problems(current, { 'category' => 'UTILITY' })).to eq(['category_change_not_allowed'])
      expect(described_class.edit_problems(current.merge('status' => 'APPROVED'), { 'category' => 'utility' }))
        .to eq(['category_change_not_allowed'])
    end

    it 'aceita a mesma categoria (sem diferença de maiúsculas) ou edição sem categoria' do
      expect(described_class.edit_problems(current, { 'category' => 'marketing' })).to eq([])
      expect(described_class.edit_problems(current, { 'components' => [] })).to eq([])
    end
  end
end
