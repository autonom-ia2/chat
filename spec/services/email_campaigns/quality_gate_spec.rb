require 'rails_helper'

RSpec.describe EmailCampaigns::QualityGate, :aggregate_failures do
  let(:font) { 'font-family="Arial, Helvetica, sans-serif"' }
  let(:footer) do
    <<~MJML
      <mj-section background-color="#f4f4f4" css-class="footer-locked">
        <mj-column>
          <mj-text #{font} font-size="12px" color="#4b5563">Empresa<br/><a href="{{ unsubscribe_url }}" style="color:#4b5563;">Cancelar inscrição</a></mj-text>
        </mj-column>
      </mj-section>
    MJML
  end
  let(:html) { '<html><body><a href="{{ unsubscribe_url }}">Cancelar inscrição</a></body></html>' }
  let(:public_root) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.remove_entry(public_root) }

  def template(content, footer_markup = footer)
    <<~MJML
      <mjml>
        <mj-head><mj-title>Olá, {{ nome }}</mj-title></mj-head>
        <mj-body width="600px" background-color="#ffffff">
          <mj-section background-color="#ffffff"><mj-column>#{content}</mj-column></mj-section>
          #{footer_markup}
        </mj-body>
      </mjml>
    MJML
  end

  def text(attrs = %(#{font} font-size="16px" color="#1f2937"), body = 'Olá, {{ nome }}')
    "<mj-text #{attrs}>#{body}</mj-text>"
  end

  def checks(mjml, html: self.html, compile_errors: [])
    described_class.new(mjml: mjml, html: html, compile_errors: compile_errors, public_root: public_root)
                   .violations.map(&:check)
  end

  it 'accepts an accessible, editable template with one locked unsubscribe footer' do
    button = %(<mj-button #{font} font-size="16px" line-height="20px" inner-padding="12px 24px" \
               background-color="#0f766e" color="#ffffff" href="https://exemplo.com.br">Ver</mj-button>)

    expect(checks(template(text + button))).to be_empty
  end

  it 'reports strict MJML validation errors from the compiler' do
    expect(checks(template(text), compile_errors: ['mj-text cannot be used inside mj-section'])).to eq([:mjml_strict])
  end

  it 'rejects blocks the editor cannot edit' do
    %w[mj-raw mj-table mj-hero mj-navbar mj-carousel mj-accordion].each do |tag|
      expect(checks(template(text + "<#{tag}></#{tag}>"))).to include(:editable_tags)
    end
    expect(checks(template(text(%(#{font} font-size="16px" color="#1f2937"), '<div>x</div>')))).to include(:editable_tags)
  end

  it 'rejects self-closed MJML tags' do
    expect(checks(template("#{text}<mj-divider border-color=\"#000000\" />"))).to include(:explicit_close_tags)
    expect(checks(template(text))).not_to include(:explicit_close_tags)
  end

  it 'demands exactly one locked footer carrying the only unsubscribe link' do
    expect(checks(template(text, ''))).to include(:unsubscribe)
    expect(checks(template(text, footer + footer))).to include(:unsubscribe)
    expect(checks(template(text(%(#{font} font-size="16px" color="#1f2937"), '<a href="{{ unsubscribe_url }}">Sair</a>')))).to include(:unsubscribe)
    expect(checks(template(text), html: "#{html}#{html}")).to include(:unsubscribe)
  end

  it 'measures text contrast against the nearest background, relaxing it only for large bold text' do
    expect(checks(template(text(%(#{font} font-size="16px" color="#9ca3af"))))).to include(:contrast)
    expect(checks(template(text(%(#{font} font-size="16px" color="#1f2937"), '<span style="color:#d1d5db">claro</span>')))).to include(:contrast)
    # #808080 on white is 3.95:1 — enough only for >= 24px bold.
    expect(checks(template(text(%(#{font} font-size="24px" font-weight="700" color="#808080"))))).not_to include(:contrast)
    expect(checks(template(text(%(#{font} font-size="18px" font-weight="700" color="#808080"))))).to include(:contrast)
    dark = '<mj-section background-color="#0b1736"><mj-column>' \
           "#{text(%(#{font} font-size="16px" color="#ffffff"))}</mj-column></mj-section>"
    expect(checks(template(text).sub('<mj-section background-color="#ffffff">', "#{dark}<mj-section background-color=\"#ffffff\">")))
      .not_to include(:contrast)
  end

  it 'checks button text contrast and the 44px touch height' do
    low = %(<mj-button #{font} font-size="16px" line-height="20px" inner-padding="12px 24px" \
            background-color="#fde047" color="#ffffff">Ver</mj-button>)
    short = %(<mj-button #{font} font-size="14px" inner-padding="10px 25px" background-color="#0f766e" color="#ffffff">Ver</mj-button>)

    expect(checks(template(text + low))).to include(:contrast)
    expect(checks(template(text + short))).to include(:button_height)
  end

  it 'keeps body text at 14px or more and the footer at 12px or more, in explicit Arial' do
    expect(checks(template(text(%(#{font} font-size="13px" color="#1f2937"))))).to include(:font_size)
    expect(checks(template(text(%(font-size="16px" color="#1f2937"))))).to include(:font_family)
    expect(checks(template(text(%(font-family="Ubuntu, sans-serif" font-size="16px" color="#1f2937"))))).to include(:font_family)
    expect(checks(template(text))).not_to include(:font_size)
  end

  it 'accepts only described images served by the installation, up to 200 KB' do
    public_root.join('email-templates').mkpath
    public_root.join('email-templates/ok.jpg').binwrite('x' * 1024)
    public_root.join('email-templates/big.jpg').binwrite('x' * ((200 * 1024) + 1))

    expect(checks(template(%(#{text}<mj-image src="/email-templates/ok.jpg" alt="Foto"></mj-image>)))).to be_empty
    expect(checks(template(%(#{text}<mj-image src="/email-templates/ok.jpg"></mj-image>)))).to include(:image_alt)
    expect(checks(template(%(#{text}<mj-image src="https://cdn.exemplo.com/a.jpg" alt="Foto"></mj-image>)))).to include(:local_images)
    expect(checks(template(%(#{text}<mj-image src="/email-templates/falta.jpg" alt="Foto"></mj-image>)))).to include(:local_images)
    expect(checks(template(%(#{text}<mj-image src="/../outside.jpg" alt="Foto"></mj-image>)))).to include(:local_images)
    expect(checks(template(%(#{text}<mj-image src="/email-templates/big.jpg" alt="Foto"></mj-image>)))).to include(:local_images)
  end

  it 'keeps the compiled HTML under the 102 KB Gmail clipping limit' do
    expect(checks(template(text), html: html + ('x' * 102 * 1024))).to include(:html_size)
  end

  it 'accepts only placeholders every campaign can fill' do
    expect(checks(template(text(%(#{font} font-size="16px" color="#1f2937"), 'CPF {{ cpf }}')))).to include(:placeholders)
    expect(checks(template(text(%(#{font} font-size="16px" color="#1f2937"), '{{ contact.email }}')))).not_to include(:placeholders)
  end

  it 'exposes the locked footer so a library can require it to be identical everywhere' do
    footers = described_class.locked_footers(template(text))

    expect(footers.size).to eq(1)
    expect(footers.first).to include('footer-locked', '{{ unsubscribe_url }}')
    expect(described_class.locked_footers(template(text('', 'Outro')))).to eq(footers)
  end
end
