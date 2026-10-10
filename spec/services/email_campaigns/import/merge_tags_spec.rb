require 'rails_helper'

RSpec.describe EmailCampaigns::Import::MergeTags, :aggregate_failures do
  let(:report) { EmailCampaigns::Import::Report.new(source_kind: 'paste') }

  def convert(html)
    root = Nokogiri::HTML5.fragment(html)
    described_class.new(report).apply(root)
    root.to_html
  end

  def warning(code)
    report.to_h[:warnings].find { |entry| entry[:code] == code }
  end

  describe EmailCampaigns::Import::MergeTags::Tokenizer do
    it 'splits text and every supported tag syntax, giving the source back byte for byte' do
      source = 'Oi *|FNAME|*, {{ contact.EMAIL }} [[data:firstname:"x"]] %%unsubscribe%% {% if a %}fim{{{ b }}}'
      tokens = described_class.scan(source)

      expect(tokens.select(&:tag?).map(&:syntax)).to eq(%i[star_pipe mustache double_bracket percent statement mustache])
      expect(tokens.select(&:tag?).map(&:inner)).to eq(['FNAME', ' contact.EMAIL ', 'data:firstname:"x"', 'unsubscribe', ' if a ', ' b '])
      expect(tokens.map(&:raw).join).to eq(source)
    end

    it 'reads %% %% as a tag only around a name, so percentages in running text stay text' do
      expect(described_class.scan('Desconto de 10%% hoje e 20%% amanhã').none?(&:tag?)).to be(true)
      expect(described_class.scan('Oi %%FIRSTNAME%%, %%contact.first_name%% %%list:x%%').select(&:tag?).map(&:inner))
        .to eq(%w[FIRSTNAME contact.first_name list:x])
    end

    it 'keeps an opener without its closer as plain text' do
      tokens = described_class.scan('Preço {{ sem fim e 50% *| solto')

      expect(tokens.none?(&:tag?)).to be(true)
      expect(tokens.map(&:raw).join).to eq('Preço {{ sem fim e 50% *| solto')
    end
  end

  it 'maps each family of tags to our fields through closed tables' do
    out = convert('<p>{{lead.nome}} {{ lead.primeiro_nome }} {{lead.empresa}} {{lead.cargo}} {{lead.email}} ' \
                  '*|FNAME|* *|EMAIL|* *|COMPANY|* {{ contact.FIRSTNAME }} {{ contact.company }} {{ contact.jobtitle }} ' \
                  "{{ personalization_token('contact.firstname', 'tudo bem') }} [[data:firstname:\"cliente\"]] " \
                  '{{var:empresa:"a sua empresa"}} [[EMAIL_TO]]</p>')

    expect(out).to eq('<p>{{ nome }} {{ primeiro_nome }} {{ empresa }} {{ cargo }} {{ email }} {{ primeiro_nome }} {{ email }} ' \
                      '{{ empresa }} {{ primeiro_nome }} {{ empresa }} {{ cargo }} {{ primeiro_nome }} {{ primeiro_nome }} ' \
                      '{{ empresa }} {{ email }}</p>')
    expect(warning(:tags_converted)[:items]).to include({ from: '*|FNAME|*', to: '{{ primeiro_nome }}' })
  end

  it 'joins a first name followed by a last name into the full name' do
    expect(convert('<p>Olá, *|FNAME|* *|LNAME|*!</p>')).to eq('<p>Olá, {{ nome }}!</p>')
  end

  it 'keeps only the first branch of a conditional, across tags, and records the branch it drops' do
    out = convert('<p>*|IF:COMPANY|*Para a *|COMPANY|*.*|ELSE:|*Para você.*|END:IF|*</p>' \
                  '<p>{% if contact.FIRSTNAME %}Olá, {{ contact.FIRSTNAME | capitalize }}!{% else %}Olá!{% endif %}</p>' \
                  '<p>*|IFNOT:ARCHIVE_PAGE|* A <strong>B</strong><br> C *|END:IF|* depois</p>')

    expect(out).to eq('<p>Para a {{ empresa }}.</p><p>Olá, {{ primeiro_nome }}!</p><p> A <strong>B</strong><br> C  depois</p>')
    expect(report.dropped_texts).to include({ text: 'Para você.', reason: :conditional }, { text: 'Olá!', reason: :conditional })
    expect(warning(:conditional_simplified)[:count]).to eq(3)
    expect(warning(:tag_simplified)[:count]).to eq(1)
  end

  it 'rejoins a tag the editor split across inline tags' do
    expect(convert('<p>Empresa: <span>{{ </span><span>empresa }}</span>.</p>')).to eq('<p>Empresa: <span>{{ empresa }}</span><span></span>.</p>')
  end

  it 'turns unknown tags into a field of their own, listed in the report, without taking a known field by mistake' do
    out = convert('<p>{{ cupom_exclusivo }} {{lead.custom_fields.cf_regiao}} {{ owner.email }} *|MMERGE7|*</p>')

    expect(out).to eq('<p>{{ cupom_exclusivo }} {{ cf_regiao }} {{ owner_email }} {{ mmerge7 }}</p>')
    expect(warning(:unknown_fields)[:items].pluck(:key)).to eq(%w[cupom_exclusivo cf_regiao owner_email mmerge7])
    expect(warning(:unknown_fields)[:severity]).to eq(:blocking)
  end

  it 'removes links and noise that only make sense on the platform the model came from' do
    out = convert('<p><a href="*|ARCHIVE|*">Ver no navegador</a> Copyright *|CURRENT_YEAR|* *|LIST:COMPANY|* ' \
                  '{{ site_settings.company_name }} {% module "x" path="y" %} {{{ update_profile }}} fim</p>')

    expect(Nokogiri::HTML5.fragment(out).text.split.join(' ')).to eq('Copyright fim')
    expect(report.dropped_texts).to include({ text: 'Ver no navegador', reason: :platform_link })
    expect(report.dropped_links).to include({ href: '*|ARCHIVE|*', reason: :platform_link })
    expect(warning(:platform_tags_removed)[:count]).to eq(6)
  end

  it 'rewrites tags inside attributes and points every unsubscribe tag at ours' do
    out = convert('<a href="https://x.example.com/a?e={{lead.email}}&amp;c=*|UNIQID|*">a</a>' \
                  '<a href="*|UNSUB|*">sair</a><a href="{{ unsubscribe_link_all }}">sair</a><a href="[[UNSUB_LINK_PT]]">sair</a>' \
                  '<img src="https://x.example.com/i.png" alt="Oi *|FNAME|*">')

    expect(out).to eq('<a href="https://x.example.com/a?e={{ email }}&amp;c=">a</a><a href="{{ unsubscribe_url }}">sair</a>' \
                      '<a href="{{ unsubscribe_url }}">sair</a><a href="{{ unsubscribe_url }}">sair</a>' \
                      '<img src="https://x.example.com/i.png" alt="Oi {{ primeiro_nome }}">')
  end

  it 'drops unsubscribe tags written as plain text, since our footer brings the only link' do
    expect(convert('<p>Sair: {% unsubscribe %} ou %%unsubscribe%%.</p>')).to eq('<p>Sair:  ou .</p>')
  end

  it 'reads mustache sections and loops as conditionals, keeping their body once' do
    expect(convert('<p>{{#each itens}}{{descricao}}{{/each}}</p>')).to eq('<p>{{ descricao }}</p>')
  end

  it 'cleans a plain-text value such as the subject, keeping only fields' do
    expect(described_class.new(report).plain_text('{{ params.assunto | default : "Novidades" }} para *|FNAME|*')).to eq('para {{ primeiro_nome }}')
  end

  it 'does not list as unknown a field that was the whole address of a link, since that link leaves' do
    convert('<a href="{{ link_produto }}">Ver</a><p>{{ cupom }}</p>')

    expect(warning(:unknown_fields)[:items].pluck(:key)).to eq(%w[cupom])
  end
end
