require 'rails_helper'

RSpec.describe EmailCampaigns::Import::Engine, :aggregate_failures do
  let(:fixtures) { Rails.root.join('spec/fixtures/email_imports') }

  def import(name, source_kind: 'file')
    described_class.call(fixtures.join(name).read, source_kind: source_kind)
  end

  # The error code of an input the engine refuses, or nil.
  def refusal(input, source_kind: 'paste')
    described_class.call(input, source_kind: source_kind)
    nil
  rescue EmailCampaigns::Import::Error => e
    e.code
  end

  def parsed(result)
    Nokogiri::HTML5.fragment(result.mjml)
  end

  def codes(result)
    result.report.to_h[:warnings].pluck(:code)
  end

  def warning(result, code)
    result.report.to_h[:warnings].find { |entry| entry[:code] == code }
  end

  describe 'limits' do
    it 'refuses input over 500 KB, empty input, too many nodes and too deep trees, with a code the screen can explain' do
      big = 'a' * ((500 * 1024) + 1)
      many = "<table>#{'<tr><td>x</td></tr>' * 2_600}</table>"
      deep = "#{'<div>' * 45}x#{'</div>' * 45}"

      expect(refusal(big)).to eq(:too_large)
      expect(refusal(" \n ")).to eq(:empty)
      expect(refusal(many)).to eq(:too_many_nodes)
      expect(refusal(deep)).to eq(:too_deep)
      expect(refusal('<p>x</p>', source_kind: 'ftp')).to eq(:invalid_source_kind)
    end

    it 'turns only the parser depth stop into the depth code, letting any other parser error through' do
      allow(Nokogiri).to receive(:HTML5).and_raise(ArgumentError, 'Document tree depth limit exceeded')
      expect { EmailCampaigns::Import::Limits.html!('<p>x</p>') }
        .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:too_deep) }

      allow(Nokogiri).to receive(:HTML5).and_raise(ArgumentError, 'outra coisa')
      expect { EmailCampaigns::Import::Limits.html!('<p>x</p>') }.to raise_error(ArgumentError, 'outra coisa')
    end

    it 'refuses a model without any text or image' do
      expect(refusal('<form><input name="senha"></form>')).to eq(:empty)
    end

    it 'refuses MJML it cannot parse instead of keeping it as written' do
      expect(refusal('<mjml><mj-body><mj-section></mjml>')).to eq(:malformed_mjml)
    end
  end

  it 'imports the drag-and-drop export with its hero, three columns, button, fields and our footer' do
    result = import('rdstation.html')
    out = parsed(result)

    expect(out.at('mj-preview').text).to eq('Seu convite para o encontro de clientes chegou')
    expect(out.css('mj-section').find { |section| section['background-url'] }['background-url'])
      .to eq('https://d335luupugsy2.cloudfront.example.com/cms/files/123456/1700000001banner.jpg')
    expect(out.css('mj-section').map { |section| section.css('mj-column').size }).to include(3)
    expect(out.css('mj-button').map(&:text)).to eq(['Confirmar presença'])
    expect(result.mjml).to include('{{ nome }}, você está convidado!', 'Oi, <strong>{{ primeiro_nome }}</strong>.', '{{ empresa }}', '{{ cargo }}')
    expect(warning(result, :unknown_fields)[:items].pluck(:key)).to eq(%w[cf_regiao])
    expect(EmailCampaigns::QualityGate.locked_footers(result.mjml).size).to eq(1)
    expect(result.mjml.scan('{{ unsubscribe_url }}').size).to eq(1)
    expect(result.mjml).not_to include('Descadastrar', 'Gerenciar preferências', 'tracking.rdstation')
    expect(codes(result)).to include(:footer_replaced, :tracking_removed, :preheader_kept, :images_to_copy, :tags_converted, :font_replaced)
  end

  it 'follows the MJML path when the pasted model is MJML, turning blocks the editor cannot edit into editable ones' do
    result = import('mailjet.html', source_kind: 'paste')
    out = parsed(result)
    names = out.css('*').map(&:name).uniq

    expect(names).not_to include('mj-hero', 'mj-navbar', 'mj-table', 'mj-accordion', 'mj-raw', 'mj-include', 'mj-font', 'mj-style')
    expect(out.at('mj-title').text).to eq('Agenda de outubro')
    expect(out.css('mj-section').find { |section| section['background-url'] }['background-url'])
      .to eq('https://xxxxx.mjt.lu.example.com/img/abc123/hero.jpg')
    expect(result.mjml).to include('Olá, {{ primeiro_nome }}', 'para {{ empresa }}', 'Dia — Horário — Vagas', 'Preciso levar algo?',
                                   'https://exemplo-clinica.example.com/agenda', 'Serviços')
    expect(result.mjml).not_to include('onclick', 'alert(1)', '[[UNSUB_LINK_PT]]', '[[PERMALINK]]')
    expect(out.css('mj-image[css-class="import-unresolved"]').size).to eq(1)
    expect(codes(result)).to include(:hero_converted, :navbar_converted, :accordion_converted, :table_as_text, :include_ignored,
                                     :unresolved_parts, :web_font_ignored, :styles_dropped)
  end

  it 'keeps the body that shares its cell with the footer, taking out only the footer lines' do
    result = import('rodape-na-mesma-celula.html')
    body = parsed(result).css('mj-section').reject { |section| section['css-class'].to_s.include?('footer-locked') }.map(&:text).join

    expect(body).to include('coleção de outono', 'Frete grátis', 'OUTONO10', '{{ primeiro_nome }}')
    expect(body).not_to include('Descadastre-se', 'Rua das Flores')
    expect(result.mjml.scan('{{ unsubscribe_url }}').size).to eq(1)
  end

  it 'keeps a white headline over a banner image, with the image and its color untouched' do
    result = import('banner-texto-branco.html')
    out = parsed(result)
    banner = out.css('mj-section').find { |section| section['background-url'] }

    expect(banner['background-url']).to eq('https://img.loja-exemplo.example.com/black-friday.jpg')
    expect(banner.css('mj-text').map(&:text).join).to include('Black Friday 70% OFF', 'Só nesta sexta')
    expect(banner.css('mj-text').pluck('color').uniq).to eq(['#ffffff'])
    expect(result.report.dropped_texts.pluck(:reason)).not_to include(:hidden)
  end

  it 'corrects quality problems on its own and lists what it could not' do
    result = import('mailchimp.html')
    violations = EmailCampaigns::QualityGate.new(mjml: result.mjml, remote_images: true,
                                                 placeholders: described_class::PLACEHOLDERS).violations

    expect(violations.map(&:check).uniq - %i[local_images]).to eq([])
    expect(warning(result, :quality_fixed)[:items]).to include('contrast', 'font_size', 'image_alt')
    expect(result.report.to_h[:counts]).to include(:sections, :columns, :texts, :images)
  end

  it 'reports in a shape the screen can read, naming no platform' do
    report = import('hubspot.html').report.to_h

    expect(report.keys).to include(:version, :source_kind, :title, :preheader, :editable_area_ratio, :counts, :warnings, :images,
                                   :unresolved, :dropped)
    expect(report[:warnings]).to all(include(:key, :code, :severity, :count, :items))
    expect(report[:warnings].pluck(:key)).to all(start_with('EMAIL_IMPORT.REPORT.'))
    expect(report[:images]).to all(include(:src, :kind))
    expect(report[:warnings].to_json.downcase).not_to include('hubspot', 'mailchimp', 'brevo', 'rd station', 'mailjet')
  end
end
