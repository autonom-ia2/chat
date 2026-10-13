require 'rails_helper'

# #1335: o canal de campanha do redator — o mesmo texto livre do whatsapp_texto, com o prompt de campanha. A IA é
# simulada aqui: nenhum spec chama IA paga.
RSpec.describe Ai::Redacao::Canais::WhatsappCampanha do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:permitidas) { %w[cliente.primeiro_nome minha_empresa.nome publico.Link_da_oferta] }

  around { |example| with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run } }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def responde(*textos)
    opcoes = textos.map do |texto|
      { texto: texto, chaves_usadas: [], o_que_mudou: nil, categoria_prevista: 'divulgacao', certeza_categoria: nil, motivo_categoria: nil }
    end
    allow(client).to receive(:create).and_return(text: { status: 'ok', pergunta: nil, sugestoes: [], problemas_encontrados: [],
                                                         opcoes: opcoes }.to_json)
  end

  def escrever
    Ai::Redacao::Escrever.call(account: account, feature: 'campanha_redacao', canal: 'whatsapp_campanha', proposito: 'campanha',
                               limites: { max_chars: 1000 }, chaves: { permitidas: permitidas, obrigatorias: [] },
                               pedido: 'avisar da coleção nova')
  end

  # A herança pegaria o prompt do agendamento em silêncio: o nome próprio troca o arquivo (condição do Agendamento).
  it 'tem nome próprio e carrega prompts/whatsapp_campanha.md, não o whatsapp_texto.md' do
    pasta = Rails.root.join('app/services/ai/redacao/prompts')
    esperado = [File.read(pasta.join('comum.md')), File.read(pasta.join('whatsapp_campanha.md'))].join("\n\n")

    expect(described_class.nome).to eq('whatsapp_campanha')
    expect(described_class.prompt).to eq(esperado)
    expect(described_class.prompt).not_to include(File.read(pasta.join('whatsapp_texto.md')))
    expect(Ai::Redacao::Canais::WhatsappTexto.prompt).not_to include('Canal: mensagem de campanha')
  end

  it 'descarta a opção com link escrito à mão e fica com a do link pelo campo, sem categoria' do
    responde('Oi, {{cliente.primeiro_nome}}! Veja em www.loja.com.br as novidades.',
             'Oi, {{cliente.primeiro_nome}}! As peças novas estão aqui: {{publico.Link_da_oferta}}. Quer que eu separe a sua?')

    resultado = escrever

    expect(resultado[:opcoes].map { |opcao| opcao[:texto] }).to eq(
      ['Oi, {{cliente.primeiro_nome}}! As peças novas estão aqui: {{publico.Link_da_oferta}}. Quer que eu separe a sua?']
    )
    expect(resultado[:opcoes].first[:categoria_prevista]).to be_nil
    expect(resultado[:descartadas]).to eq(1)
  end

  # Bateria #1335: com o link no fim ("...: {{publico.Link_da_oferta}}."), o texto de campanha é bom; só o modelo da
  # Meta recusa campo na ponta. O whatsapp_texto continua descartando (spec dele intocado).
  it 'aceita campo no começo e no fim do texto de campanha' do
    responde('Hoje a loja toda está com 50% de desconto. Veja: {{publico.Link_da_oferta}}.',
             '{{cliente.primeiro_nome}}, chegou a coleção nova. Quer ver?')

    expect(escrever[:opcoes].size).to eq(2)
    no_texto = Ai::Redacao::Canais::WhatsappTexto.validar(
      { 'texto' => 'Veja: {{publico.Link_da_oferta}}.' }, chaves: { permitidas: permitidas, obrigatorias: [] }, limites: { max_chars: 1000 }
    )
    expect(no_texto).to eq(:campo_no_fim)
  end

  it 'o link_inventado? público do whatsapp_texto acusa só o texto fixo' do
    expect(Ai::Redacao::Canais::WhatsappTexto.link_inventado?('Veja www.x.com')).to be(true)
    expect(Ai::Redacao::Canais::WhatsappTexto.link_inventado?('Veja {{publico.Link_da_oferta}}. Até.')).to be(false)
  end
end
