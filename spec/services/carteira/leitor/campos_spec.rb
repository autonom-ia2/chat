require 'rails_helper'

# E6 (#2899): a pergunta ao modelo. O modelo é um dublê; nenhuma chamada paga sai daqui. Dados fictícios.
RSpec.describe Carteira::Leitor::Campos do
  let(:account) { create(:account) }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:pagina) { Carteira::Leitor::Paginas::Pagina }
  let(:paginas) do
    [pagina.new(numero: 3, texto: 'SEGURADORA EXEMPLO S.A. Apólice nº EX-2026.001234. Vigência: 12/11/2026 a 12/11/2027.'),
     pagina.new(numero: 7, texto: 'Segurado: Marina Exemplo de Souza, CPF 123.456.789-00. Prêmio total: R$ 2.254,98.')]
  end
  let(:esquema) { described_class.schema[:schema] }

  before { Carteira::Leitor::Liberado.ligar!(account) }

  def responde(campos)
    allow(cliente).to receive(:create).and_return({ text: esquema[:required].index_with { nil }.merge(campos).to_json, usage: {} })
  end

  def pergunta(account: self.account, cliente: self.cliente)
    described_class.new(account: account, cliente: cliente)
  end

  # Achado H da revisão: quem paga é esta classe, então a trava da conta é dela também.
  describe 'a trava de quem paga' do
    it 'conta sem a leitura liberada: levanta Desligada antes de qualquer chamada, mesmo com um cliente na mão' do
      Carteira::Leitor::Liberado.desligar!(account)
      responde('e_apolice' => true)
      allow(Crm::Ai::ResponsesClient).to receive(:new)

      expect { pergunta.ler(paginas) }.to raise_error(described_class::Desligada)
      expect { pergunta(cliente: nil).ler(paginas) }.to raise_error(described_class::Desligada)
      expect { pergunta(account: nil).ler(paginas) }.to raise_error(described_class::Desligada)
      expect(cliente).not_to have_received(:create)
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'conta liberada e sem a IA configurada: levanta SemIa, sem criar cliente' do
      allow(Crm::Ai::ResponsesClient).to receive(:new)

      expect { pergunta(cliente: nil).ler(paginas) }.to raise_error(described_class::SemIa)
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'conta liberada e com a IA configurada: o cliente nasce com a credencial da conta, a feature e uma nova tentativa' do
      allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
      create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
      responde('e_apolice' => false)

      pergunta(cliente: nil).ler(paginas)

      expect(Crm::Ai::ResponsesClient).to have_received(:new)
        .with(credential: hash_including(api_key: 'chave-da-conta'), feature: 'carteira_leitor', account: account, max_retries: 1)
    end
  end

  it 'o esquema é fechado: todo campo é obrigatório, aceita null, e não cabe campo a mais' do
    de_fora = esquema[:properties].except('e_apolice').reject { |_campo, forma| forma[:type].include?('null') }

    expect(esquema).to include(type: 'object', additionalProperties: false, required: esquema[:properties].keys)
    expect(de_fora).to be_empty
    expect(esquema[:properties]['e_apolice']).to eq(type: 'boolean')
    expect(esquema[:properties]['tipo'][:enum]).to eq(Carteira::Apolice::TIPOS + [nil])
  end

  it 'manda só as páginas recebidas, com o número de cada uma, e as instruções fixas' do
    responde('e_apolice' => true)

    pergunta.ler(paginas)

    expect(cliente).to have_received(:create).with(
      model: described_class::MODEL, instructions: described_class::INSTRUCTIONS, schema: described_class.schema,
      input: { paginas: [{ numero: 3, texto: paginas.first.texto }, { numero: 7, texto: paginas.last.texto }] }.to_json,
      reasoning_effort: described_class::EFFORT, timeout: described_class::TIMEOUT, max_output_tokens: described_class::MAX_OUTPUT_TOKENS
    )
  end

  it 'devolve os campos conferidos e a resposta crua, para o contato do segurado' do
    resposta = { 'e_apolice' => true, 'tipo' => 'auto', 'seguradora' => 'Seguradora Exemplo S.A.', 'numero' => 'EX-2026.001234',
                 'fim_vigencia' => '2027-11-12', 'valor_centavos' => 225_498, 'segurado_documento' => '123.456.789-00',
                 'segurado_telefone' => '(11) 99999-0001', 'segurado_telefone_pagina' => 7, 'bem' => 'Caminhão Fantasma' }
    responde(resposta)

    lido = pergunta.ler(paginas)

    expect(lido.e_apolice).to be(true)
    expect(lido.campos).to eq('tipo' => 'auto', 'ramo_original' => nil, 'seguradora' => 'Seguradora Exemplo S.A.', 'numero' => 'EX-2026.001234',
                              'inicio_vigencia' => nil, 'fim_vigencia' => '2027-11-12', 'valor_centavos' => 225_498, 'bem' => nil,
                              'corretora' => nil, 'segurado_nome' => nil, 'segurado_documento' => '12345678900')
    expect(lido.resposta).to include('segurado_telefone' => '(11) 99999-0001', 'segurado_telefone_pagina' => 7)
  end

  it 'não é apólice: sem campo nenhum, mesmo que o modelo mande algum' do
    responde('e_apolice' => false, 'numero' => 'EX-2026.001234')

    expect(pergunta.ler(paginas)).to have_attributes(e_apolice: false, campos: {}, resposta: {})
  end

  it 'qualquer quebra da chamada vira Falhou, só com a classe do erro' do
    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('Marina Exemplo de Souza 123.456.789-00'))

    expect { pergunta.ler(paginas) }.to raise_error(described_class::Falhou, 'Crm::Ai::ResponsesClient::Error')
  end

  it 'a feature do leitor aparece na Gestão IA como Carteira de seguros' do
    expect(Crm::Reports::AiUsage.resource_for_feature(described_class::FEATURE)).to eq('Carteira de seguros')
  end
end
