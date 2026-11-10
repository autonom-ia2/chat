require 'rails_helper'

# #2850 (Refs #1431) — prazo no embedding da pergunta. Cada tentativa tem prazo curto; numa falha passageira (prazo,
# conexão, provedor, limite de taxa), uma nova tentativa só se couber no orçamento, e no máximo uma. Sem vetor, com a
# busca híbrida ligada, a busca segue só pela palavra; sem ela, o caminho de hoje (lista vazia). Toda falha deixa linha
# de log com o motivo. O placar (`retrieve!`) continua levantando.
RSpec.describe Autonomia::Agents::Retriever do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let(:embedding_service) { instance_double(Autonomia::Agents::EmbeddingService) }
  let(:perto) { Array.new(1536) { 0.01 } }
  let(:source) { agent.sources.create!(account: account, source_type: 'pdf', status: :ready, reference: 'cg.pdf') }
  let(:pergunta) { 'Qual o telefone do aviso de sinistro?' }
  let(:prazo) { Autonomia::Agents::Config::PRAZO_DO_EMBEDDING_S }
  let(:orcamento) { Autonomia::Agents::Config::ORCAMENTO_DO_EMBEDDING_S }
  let(:retriever) { described_class.new(agent: agent.reload) }

  def entry(indice, content, **opcoes)
    alvo = opcoes.fetch(:alvo, agent)
    alvo.knowledge_entries.create!(account: alvo.account, source: opcoes.fetch(:fonte, source), content: content,
                                   status: :ready, chunk_index: indice, metadata: opcoes.fetch(:metadata, {}), embedding: perto)
  end

  def passageira(motivo = 'prazo')
    Autonomia::Agents::EmbeddingService::Passageira.new(motivo)
  end

  # O relógio da espera pelo vetor, em segundos, uma leitura por valor.
  def relogio(*leituras)
    allow(Autonomia::Agents::VetorDaPergunta).to receive(:agora).and_return(*leituras)
  end

  # O Answerer pede a busca só pela palavra quando falta o vetor; os demais chamadores não.
  def buscar(por_palavra_sem_vetor: true)
    retriever.retrieve(pergunta, top_k: 3, por_palavra_sem_vetor: por_palavra_sem_vetor)
  end

  before do
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(Rails.logger).to receive(:warn)
    entry(0, 'Aviso de sinistro: ligue para o telefone 0800 000 0000.')
    entry(1, 'Reboque e chaveiro em todo o Brasil.')
  end

  it 'asks the embedding with the short deadline of the question' do
    allow(embedding_service).to receive(:embed).and_return(perto)

    buscar

    expect(Autonomia::Agents::EmbeddingService).to have_received(:new).with(account: account, model: anything, prazo: prazo)
  end

  it 'measures without the deadline of the question on the path of the placar' do
    allow(embedding_service).to receive(:embed).and_return(perto)

    retriever.retrieve!(pergunta, top_k: 3)

    expect(Autonomia::Agents::EmbeddingService).to have_received(:new).with(account: account, model: anything, prazo: nil)
  end

  it 'tries once more when the second attempt fits, and finds by the vector', :aggregate_failures do
    relogio(0.0, prazo)
    chamadas = 0
    allow(embedding_service).to receive(:embed) do
      chamadas += 1
      raise passageira if chamadas == 1

      perto
    end

    resultado = buscar

    expect(chamadas).to eq(2)
    expect(resultado).not_to be_empty
    expect(resultado.map(&:neighbor_distance)).to all(be_present)
  end

  it 'does not try again when the second attempt does not fit in the budget' do
    relogio(0.0, orcamento - prazo + 0.01, orcamento)
    allow(embedding_service).to receive(:embed).and_raise(passageira)

    buscar

    expect(embedding_service).to have_received(:embed).once
  end

  it 'tries at most twice, even when the failures are fast' do
    relogio(0.0, 0.01, 0.02, 0.03)
    allow(embedding_service).to receive(:embed).and_raise(passageira('conexao'))

    buscar

    expect(embedding_service).to have_received(:embed).twice
  end

  it 'does not try again on a lasting failure (no key), and logs its reason', :aggregate_failures do
    account.enable_features!('rag_busca_hibrida')
    allow(embedding_service).to receive(:embed).and_raise(Autonomia::Agents::EmbeddingService::EmbeddingError, 'ai_not_configured')

    expect(buscar).to eq([])
    expect(embedding_service).to have_received(:embed).once
    expect(Rails.logger).to have_received(:warn).with(include('degraded', 'motivo=ai_not_configured'))
  end

  context 'with the hybrid search on' do
    before do
      account.enable_features!('rag_busca_hibrida')
      relogio(0.0, prazo, 2 * prazo)
      allow(embedding_service).to receive(:embed).and_raise(passageira)
    end

    it 'goes on by the words of the question, without a made-up distance', :aggregate_failures do
      resultado = buscar

      expect(resultado.map(&:content)).to eq(['Aviso de sinistro: ligue para o telefone 0800 000 0000.'])
      expect(resultado.first.neighbor_distance).to be_nil
    end

    it 'logs the reason, the attempts and the path taken' do
      buscar

      expect(Rails.logger).to have_received(:warn)
        .with(include('[autonomia][retriever] embedding_falhou', "agent=#{agent.id}", 'motivo=prazo', 'tentativas=2',
                      'segue=so_palavra'))
    end

    it 'keeps the isolation: another agent and a rejected source stay out', :aggregate_failures do
      outro = Autonomia::Agents::Agent.create!(account: account, name: 'Outro', agent_type: 'custom', status: :active,
                                               enabled: true, instruction: 'x')
      fonte_do_outro = outro.sources.create!(account: account, source_type: 'pdf', status: :ready, reference: 'o.pdf')
      entry(0, 'Aviso de sinistro do outro agente, telefone 0800 111.', alvo: outro, fonte: fonte_do_outro)
      reprovada = agent.sources.create!(account: account, source_type: 'pdf', status: :ready, reference: 'r.pdf')
      entry(5, 'Aviso de sinistro reprovado, telefone 0800 222.', fonte: reprovada)
      allow_any_instance_of(described_class).to receive(:rejected_source_ids).and_return([reprovada.id]) # rubocop:disable RSpec/AnyInstance

      conteudos = buscar.map(&:content)

      expect(conteudos).to include('Aviso de sinistro: ligue para o telefone 0800 000 0000.')
      expect(conteudos.join).not_to include('outro agente', 'reprovado')
    end

    it 'gives the section of an item without a distance, never 0' do
      secao = entry(10, 'Seção de assistência: reboque, chaveiro e aviso.')
      entry(11, 'Item: telefone do aviso de sinistro 0800 333.', metadata: { 'material_type' => 'item', 'trecho_da_secao' => 10 })

      encontrado = buscar.find { |trecho| trecho.id == secao.id }

      expect(encontrado.neighbor_distance).to be_nil
    end

    it 'gives [] to the callers that did not ask for the words (Ajudante, Guia)' do
      expect(buscar(por_palavra_sem_vetor: false)).to eq([])
    end

    it 'counts the failure by day, account, reason and path, for 30 days', :aggregate_failures do
      chave = Autonomia::Agents::VetorDaPergunta.chave(account.id, 'prazo', 'so_palavra')
      Redis::Alfred.delete(chave)

      2.times { buscar }

      expect(Redis::Alfred.get(chave).to_i).to eq(2)
      expect(Redis::Alfred.ttl(chave)).to be_between(1, 30.days.to_i)
    ensure
      Redis::Alfred.delete(chave)
    end

    it 'keeps the words when the counter of the failure is slow (Redis pool busy)' do
      allow(Redis::Alfred).to receive(:incr).and_raise(ConnectionPool::TimeoutError)

      expect(buscar.map(&:content)).to eq(['Aviso de sinistro: ligue para o telefone 0800 000 0000.'])
    end

    it 'does not count the failures of the placar with the traffic of the customers' do
      allow(Redis::Alfred).to receive(:incr)

      expect { retriever.retrieve!(pergunta, top_k: 3) }.to raise_error(Autonomia::Agents::EmbeddingService::Passageira)
      expect(Redis::Alfred).not_to have_received(:incr)
    end

    it 'keeps another account out, even with the same words' do
      outra = create(:account)
      dono = Autonomia::Agents::Agent.create!(account: outra, name: 'Outro', agent_type: 'custom', status: :active, enabled: true,
                                              instruction: 'x')
      fonte = dono.sources.create!(account: outra, source_type: 'pdf', status: :ready, reference: 'o.pdf')
      entry(0, 'Aviso de sinistro da outra conta, telefone 0800 444.', alvo: dono, fonte: fonte)

      expect(buscar.map(&:content).join).not_to include('outra conta')
    end

    it 'reads the material of the post only in the turn of that comment' do
      cuidado = create(:crm_meta_ads_comment_care, account: account)
      fonte = Autonomia::Agents::Source.create!(account: account, agent: agent, care: cuidado, source_type: 'txt', kind: 'knowledge',
                                                status: :ready, reference: 'post.txt')
      entry(0, 'Aviso de sinistro do post, telefone 0800 555.', fonte: fonte)

      expect(buscar.map(&:content).join).not_to include('do post')
      expect(described_class.new(agent: agent.reload, care_id: cuidado.id)
        .retrieve(pergunta, top_k: 3, por_palavra_sem_vetor: true).map(&:content).join).to include('do post')
    end

    it 'still raises on the path that measures the search (placar)' do
      expect { retriever.retrieve!(pergunta, top_k: 3) }
        .to raise_error(Autonomia::Agents::EmbeddingService::Passageira)
    end
  end

  context 'with the hybrid search off' do
    before do
      relogio(0.0, prazo, 2 * prazo)
      allow(embedding_service).to receive(:embed).and_raise(passageira)
    end

    it 'keeps the path of today (empty list), with the reason in the log', :aggregate_failures do
      expect(buscar).to eq([])
      expect(Rails.logger).to have_received(:warn).with(include('embedding_falhou', 'motivo=prazo', 'segue=sem_busca'))
    end
  end
end
