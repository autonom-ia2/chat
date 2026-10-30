require 'rails_helper'

# #1426 (t4e) — o resumo de cada seção de um PDF grande (os trechos marcados com `paginas` pelo Ingestor), para o índice
# que o Construtor e o Revisor leem. IA stubada: nenhuma chamada real.
RSpec.describe Autonomia::Agents::Knowledge::ResumoPorSecao do
  let(:account) { create(:account) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'support') }
  let(:source) do
    Autonomia::Agents::Source.create!(account: account, agent: agent, source_type: 'pdf', status: :processing)
  end
  let!(:token) { source.begin_ingestion! }
  let(:resolver) { instance_double(Crm::Ai::CredentialResolver, resolve: 'cred') }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:secoes) do
    { [1, 25] => 'Coberturas basicas contra colisao e incendio.',
      [26, 50] => 'Franquia reduzida para carros de passeio.',
      [201, 225] => 'Assistencia 24 horas com guincho ate 200 km.' }
  end

  def criar_trechos(por_secao)
    por_secao.each_with_index do |(paginas, texto), indice|
      Autonomia::Agents::KnowledgeEntry.create!(
        account: account, agent: agent, source: source, chunk_index: indice, status: :ready, content: texto,
        metadata: { 'paginas' => paginas }
      )
    end
  end

  def resposta(resumo, temas)
    { text: { resumo: resumo, temas: temas }.to_json }
  end

  def resumo_gravado
    source.reload.metadata[Autonomia::Agents::Source::RESUMO_POR_SECAO]
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    source.mark_ready!(token, chunk_count: 3)
  end

  context 'with a sectioned material' do
    before { criar_trechos(secoes) }

    it 'summarizes every section, in page order, and records the index on the material' do
      allow(client).to receive(:create).and_return(
        resposta('Coberturas basicas.', ['Coberturas']),
        resposta('Franquia reduzida.', ['Franquia']),
        resposta('Assistencia 24 horas com guincho.', ['Assistencia 24 horas'])
      )

      described_class.new(source: source, token: token).gravar!

      expect(resumo_gravado).to eq(
        [{ 'paginas' => [1, 25], 'resumo' => 'Coberturas basicas.', 'temas' => ['Coberturas'] },
         { 'paginas' => [26, 50], 'resumo' => 'Franquia reduzida.', 'temas' => ['Franquia'] },
         { 'paginas' => [201, 225], 'resumo' => 'Assistencia 24 horas com guincho.', 'temas' => ['Assistencia 24 horas'] }]
      )
    end

    it 'sends the text of the section as data, never in the instructions' do
      enviados = []
      allow(client).to receive(:create) do |**args|
        enviados << args
        resposta('Resumo.', [])
      end

      described_class.new(source: source, token: token).gravar!

      ultima = enviados.last
      expect(ultima[:input].to_json).to include('guincho ate 200 km')
      expect(ultima[:instructions]).not_to include('guincho')
      expect(enviados.size).to eq(3)
    end

    it 'caps the topics and the summary the model returns' do
      allow(client).to receive(:create).and_return(resposta('x' * 2_000, (1..20).map { |n| "Tema #{n}" }))

      described_class.new(source: source, token: token).gravar!

      primeira = resumo_gravado.first
      expect(primeira['temas'].size).to eq(described_class::TEMAS_POR_SECAO)
      expect(primeira['resumo'].length).to be <= described_class::RESUMO_MAX_CHARS
    end

    it 'skips a section whose call failed and keeps the others' do
      allow(client).to receive(:create).and_return(resposta('Coberturas.', []))
      allow(client).to receive(:create).with(hash_including(input: satisfy { |input| input.to_json.include?('Franquia') }))
                                       .and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

      described_class.new(source: source, token: token).gravar!

      expect(resumo_gravado.pluck('paginas')).to eq([[1, 25], [201, 225]])
    end

    it 'does not write when a newer reading took over' do
      allow(client).to receive(:create).and_return(resposta('Resumo.', []))
      source.begin_ingestion!

      described_class.new(source: source, token: token).gravar!

      expect(resumo_gravado).to be_nil
    end

    it 'does not call the AI without a credential' do
      allow(resolver).to receive(:resolve).and_return(nil)
      allow(client).to receive(:create)

      described_class.new(source: source, token: token).gravar!

      expect(client).not_to have_received(:create)
      expect(resumo_gravado).to be_nil
    end
  end

  it 'does nothing for a material without sections' do
    Autonomia::Agents::KnowledgeEntry.create!(
      account: account, agent: agent, source: source, chunk_index: 0, status: :ready, content: 'Texto curto.', metadata: {}
    )
    allow(client).to receive(:create)

    described_class.new(source: source, token: token).gravar!

    expect(client).not_to have_received(:create)
    expect(resumo_gravado).to be_nil
  end
end
