require 'rails_helper'

# #1335: a mensagem escrita da conversa aberta — o que ela pode usar, o que a trava e como vira o texto de cada pessoa.
RSpec.describe CampaignJourney::ConversaAberta::Texto do
  let(:permitidas) { described_class.chaves_permitidas(['Vencimento', 'Link da oferta']) }

  it 'permite nome do cliente, da empresa, o site e as colunas do público' do
    expect(permitidas).to eq(
      ['cliente.primeiro_nome', 'cliente.nome', 'minha_empresa.nome', 'minha_empresa.site', 'publico.Vencimento',
       'publico.Link_da_oferta']
    )
  end

  it 'guarda a coluna sem espaço no texto e volta ao cabeçalho real' do
    expect(described_class.colunas(['Link da oferta'])).to eq('publico.Link_da_oferta' => 'publico.Link da oferta')
  end

  it 'lista os campos para a tela, com o cabeçalho da coluna como rótulo' do
    campos = described_class.campos(['Link da oferta'], locale: :pt_BR)

    expect(campos.pluck(:chave)).to eq(%w[cliente.primeiro_nome cliente.nome minha_empresa.nome minha_empresa.site publico.Link_da_oferta])
    expect(campos.last).to eq(chave: 'publico.Link_da_oferta', rotulo: 'Link da oferta')
    expect(campos.first[:rotulo]).to eq(TemplateFields::Catalog.label('cliente.primeiro_nome', locale: :pt_BR))
  end

  it 'aceita o texto com campos do catálogo e link vindo de campo' do
    texto = 'Oi, {{cliente.primeiro_nome}}! A coleção nova chegou: {{publico.Link_da_oferta}}. Responda aqui.'

    expect(described_class.problema(texto, permitidas: permitidas)).to be_nil
  end

  it 'aceita campo no começo e no fim (texto livre não é modelo da Meta)' do
    expect(described_class.problema('{{cliente.primeiro_nome}}, veja: {{publico.Link_da_oferta}}', permitidas: permitidas)).to be_nil
  end

  {
    '' => :vazio,
    '   ' => :vazio,
    'Oi {{cliente.primeiro_nome' => :malformado,
    'Oi {{negocio.valor}}' => :chave_fora_da_lista,
    'Veja em www.loja.com' => :link_digitado,
    'Veja https://x.y/z' => :link_digitado
  }.each do |texto, motivo|
    it "trava #{texto.inspect} por #{motivo}" do
      expect(described_class.problema(texto, permitidas: permitidas)).to eq(motivo)
    end
  end

  # Decisão da Orquestração com o Agendamento: só o link inequívoco trava; o "ponto entre letras" só avisa.
  it 'não trava, só avisa, quando parece link pela heurística de domínio' do
    %w[loja.com.br Sr.Paulo Ltda.São].each do |palavra|
      texto = "Oi, falamos com #{palavra} hoje"
      expect(described_class.problema(texto, permitidas: permitidas)).to be_nil
      expect(described_class.aviso(texto)).to eq(:parece_link)
    end
  end

  it 'não avisa quando o link vem do campo nem em texto comum' do
    expect(described_class.aviso('Veja: {{publico.Link_da_oferta}}. Chegou hoje.')).to be_nil
  end

  it 'texto vazio (nil) não avisa nem quebra' do
    expect(described_class.aviso(nil)).to be_nil
  end

  it 'o link inequívoco trava e não vira só aviso' do
    expect(described_class.aviso('Veja www.loja.com')).to be_nil
  end

  it 'trava texto maior que o limite' do
    expect(described_class.problema('a' * (described_class::MAX_CHARS + 1), permitidas: permitidas)).to eq(:longo)
  end

  it 'não confunde fim de frase nem valor em reais com link' do
    expect(described_class.problema('Chegou hoje. Custa R$ 1.250,00.', permitidas: permitidas)).to be_nil
  end

  describe '.preencher' do
    let(:valores) { { 'cliente.primeiro_nome' => 'Ana', 'publico.Link da oferta' => 'https://hub2you.com.br/o/1' } }
    let(:resolver) { instance_double(TemplateFields::Resolver) }

    before { allow(resolver).to receive(:value) { |chave| valores[chave] } }

    it 'troca cada campo pelo valor da pessoa, literal' do
      texto = 'Oi, {{cliente.primeiro_nome}}! {{publico.Link_da_oferta}}'

      colunas = described_class.colunas(['Link da oferta'])

      expect(described_class.preencher(texto, resolver, colunas: colunas)).to eq('Oi, Ana! https://hub2you.com.br/o/1')
    end

    it 'devolve nil quando falta o valor de algum campo (a pessoa recebe o modelo)' do
      expect(described_class.preencher('Oi, {{cliente.primeiro_nome}} da {{minha_empresa.nome}}', resolver)).to be_nil
    end
  end
end
