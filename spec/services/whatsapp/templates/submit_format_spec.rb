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

      it "#{label}: a campanha envia exatamente o que a tela promete" do
        sendable = Whatsapp::Templates::SendableFormat.check(pronto['corpo'])
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

    it 'recusa quantidade errada e cartão incompleto' do
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [card] }))).to eq(['carousel_cards'])
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [card, card(header: false)] })))
        .to eq(['carousel_card'])
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [card, card(text: '')] })))
        .to eq(['carousel_card'])
      no_url = card(button: { 'type' => 'URL', 'text' => 'Ver', 'url' => '' })
      expect(described_class.problems(template('MARKETING', { 'type' => 'CAROUSEL', 'cards' => [card, no_url] }))).to eq(['url_missing'])
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
end
