require 'rails_helper'

# #2850 (Refs #1431, #2854 etapa 1) — reproduz a chamada travada: um provedor de embedding que aceita a conexão e não
# responde. Sem prazo (os padrões do RubyLLM: 300 s por tentativa e até 3 repetições), a pergunta fica presa. Com o
# prazo da pergunta, o `retrieve` volta dentro do orçamento, com no máximo 2 conexões, e segue só pela palavra.
RSpec.describe Autonomia::Agents::Retriever do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let(:source) { agent.sources.create!(account: account, source_type: 'pdf', status: :ready, reference: 'cg.pdf') }
  let(:prazo) { 0.3 }
  let(:orcamento) { 0.7 }

  # Aceita toda conexão, lê o pedido e não responde nada; conta as conexões.
  let(:servidor) do
    tcp = TCPServer.new('127.0.0.1', 0)
    conexoes = Queue.new
    Thread.new do
      loop do
        cliente = tcp.accept
        conexoes << cliente
      end
    rescue IOError
      nil
    end
    { tcp: tcp, conexoes: conexoes, base: "http://127.0.0.1:#{tcp.addr[1]}/v1" }
  end

  around { |exemplo| sem_webmock { exemplo.run } }

  before do
    stub_const('Autonomia::Agents::Config::PRAZO_DO_EMBEDDING_S', prazo)
    stub_const('Autonomia::Agents::Config::ORCAMENTO_DO_EMBEDDING_S', orcamento)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste', api_base: servidor[:base] }))
    # O guarda de SSRF barra o host local; aqui ele é o provedor travado do teste.
    allow(Crm::Ai::ApiBaseGuard).to receive(:validate!).and_return(servidor[:base])
    allow(Autonomia::Agents::Config).to receive(:active_embedding_model).and_return('text-embedding-3-small')
    account.enable_features!('rag_busca_hibrida')
    agent.knowledge_entries.create!(account: account, source: source, content: 'Aviso de sinistro: telefone 0800 000 0000.',
                                    status: :ready, chunk_index: 0, metadata: {}, embedding: Array.new(1536) { 0.01 })
  end

  after do
    servidor[:tcp].close
    servidor[:conexoes].size.times { servidor[:conexoes].pop.close }
  end

  it 'reproduces the hang: without a deadline the embedding of the question is still waiting after 2 s' do
    servico = Autonomia::Agents::EmbeddingService.new(account: account, model: 'text-embedding-3-small')
    espera = Thread.new { servico.embed('telefone do aviso de sinistro') }

    expect(espera.join(2)).to be_nil
  ensure
    espera&.kill
  end

  it 'with the deadline, answers inside the budget by the words, with at most 2 connections', :aggregate_failures do
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    resultado = described_class.new(agent: agent.reload).retrieve('telefone do aviso de sinistro', top_k: 3)

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < orcamento + 0.5
    expect(resultado.map(&:content)).to eq(['Aviso de sinistro: telefone 0800 000 0000.'])
    expect(resultado.first.neighbor_distance).to be_nil
    expect(servidor[:conexoes].size).to eq(2)
  end
end
