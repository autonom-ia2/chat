require 'rails_helper'

RSpec.describe Autonomia::Agents::EmbeddingService do
  subject(:service) { described_class.new(account: account) }

  let(:account) { create(:account) }

  describe 'model resolution (B1)' do
    it 'reads the active model from Config (single source of truth)' do
      allow(Autonomia::Agents::Config).to receive(:active_embedding_model).and_return('text-embedding-3-large')
      expect(described_class.new(account: account).instance_variable_get(:@model)).to eq('text-embedding-3-large')
    end
  end

  describe '#embed_batch (B1 — real batching)' do
    let(:ctx) { instance_double(RubyLLM::Context) }

    # `context` é o seam do provider externo (RubyLLM) — stubar é o ponto de isolamento correto.
    before { allow(service).to receive(:context).and_return(ctx) } # rubocop:disable RSpec/SubjectStub

    it 'makes ONE call per batch with array input and aligns 1:1, blanks -> []' do
      # Arrange — só os não-vazios vão à API, em um único request
      expect(ctx).to receive(:embed).once.with(%w[a b], model: anything)
                                    .and_return(instance_double(RubyLLM::Embedding, vectors: [[1.0], [2.0]]))

      # Act
      result = service.embed_batch(['a', '', 'b'])

      # Assert — vazio preserva a posição como []
      expect(result).to eq([[1.0], [], [2.0]])
    end

    it 'splits into slices of EMBED_BATCH_SIZE' do
      # Arrange
      size = described_class::EMBED_BATCH_SIZE
      texts = Array.new(size + 10) { |i| "t#{i}" }
      allow(ctx).to receive(:embed).and_return(
        instance_double(RubyLLM::Embedding, vectors: Array.new(size) { [0.0] }),
        instance_double(RubyLLM::Embedding, vectors: Array.new(10) { [0.0] })
      )

      # Act
      result = service.embed_batch(texts)

      # Assert — dois requests (size + 10), saída alinhada 1:1
      expect(ctx).to have_received(:embed).twice
      expect(result.size).to eq(texts.size)
    end

    it 'normalizes a single flat vector into an array-of-arrays' do
      # Arrange — provider devolve vetor único (flat) p/ input de 1
      allow(ctx).to receive(:embed).and_return(instance_double(RubyLLM::Embedding, vectors: [1.0, 2.0, 3.0]))

      # Act
      result = service.embed_batch(['solo'])

      # Assert
      expect(result).to eq([[1.0, 2.0, 3.0]])
    end

    it 'returns [] for a blank-only list without calling the API' do
      # Assert
      expect(ctx).not_to receive(:embed)
      expect(service.embed_batch(['', nil])).to eq([[], []])
    end
  end

  # #2850 (Refs #1431) — o embedding da pergunta tem prazo próprio, sem as novas tentativas do RubyLLM (300 s e até 3
  # repetições por padrão). Quem decide se tenta de novo é o Retriever, que conhece o orçamento do turno.
  describe 'deadline of the question (#2850)' do
    let(:credencial) { instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste' }) }

    before { allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(credencial) }

    it 'sets the deadline per attempt and turns off the retries of RubyLLM', :aggregate_failures do
      config = described_class.new(account: account, prazo: 2.0).send(:context).config

      expect(config.request_timeout).to eq(2.0)
      expect(config.max_retries).to eq(0)
    end

    it 'keeps the defaults of RubyLLM without a deadline (the ingestion in background)' do
      expect(described_class.new(account: account).send(:context).config.request_timeout).to eq(RubyLLM.config.request_timeout)
    end
  end

  describe 'passing failures (#2850)' do
    let(:ctx) { instance_double(RubyLLM::Context) }

    before { allow(service).to receive(:context).and_return(ctx) } # rubocop:disable RSpec/SubjectStub

    {
      Faraday::TimeoutError.new('execution expired') => 'prazo',
      Faraday::ConnectionFailed.new('connection refused') => 'conexao',
      RubyLLM::ServerError.new(nil, 'bad gateway') => 'provedor',
      RubyLLM::ServiceUnavailableError.new(nil, 'unavailable') => 'provedor',
      RubyLLM::OverloadedError.new(nil, 'overloaded') => 'provedor',
      RubyLLM::RateLimitError.new(nil, 'slow down') => 'limite_de_taxa'
    }.each do |erro, motivo|
      it "turns #{erro.class.name} into a passing failure with the reason #{motivo}", :aggregate_failures do
        allow(ctx).to receive(:embed).and_raise(erro)
        allow(Rails.logger).to receive(:error)

        expect { service.embed('pergunta') }.to raise_error(described_class::Passageira) { |falha| expect(falha.motivo).to eq(motivo) }
        expect(Rails.logger).to have_received(:error).with(include('operation=autonomia.embedding', "error_type=#{erro.class.name}"))
      end
    end

    it 'turns Faraday::SSLError into a passing failure with the reason conexao' do
      allow(ctx).to receive(:embed).and_raise(Faraday::SSLError.new('handshake'))

      expect { service.embed('pergunta') }.to raise_error(described_class::Passageira) { |falha| expect(falha.motivo).to eq('conexao') }
    end

    it 'keeps any other network failure as a plain embedding error, with log, never loose', :aggregate_failures do
      allow(ctx).to receive(:embed).and_raise(Faraday::ParsingError.new('cut'))
      allow(Rails.logger).to receive(:error)

      expect { service.embed('pergunta') }
        .to raise_error(described_class::EmbeddingError) do |falha|
          expect([falha.class, falha.motivo]).to eq([described_class::EmbeddingError, 'provedor_recusou'])
        end
      expect(Rails.logger).to have_received(:error).with(include('error_type=Faraday::ParsingError'))
    end

    it 'cuts the whole attempt at the deadline, even when the network keeps trickling' do
      lento = described_class.new(account: account, prazo: 0.2)
      allow(lento).to receive(:context).and_return(ctx)
      allow(ctx).to receive(:embed) { sleep 2 }

      inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { lento.embed('pergunta') }.to raise_error(described_class::Passageira) { |falha| expect(falha.motivo).to eq('prazo') }
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < 1
    end

    it 'gives the label of a lasting failure without the message of the provider', :aggregate_failures do
      expect(described_class::EmbeddingError.new('ai_not_configured').motivo).to eq('ai_not_configured')
      expect(described_class::EmbeddingError.new('Failed to create an embedding: Incorrect API key sk-xx').motivo).to eq('provedor_recusou')
    end

    it 'keeps a lasting failure (wrong key) as a plain embedding error' do
      allow(ctx).to receive(:embed).and_raise(RubyLLM::UnauthorizedError.new(nil, 'bad key'))

      expect { service.embed('pergunta') }
        .to raise_error(described_class::EmbeddingError) { |falha| expect(falha).not_to be_a(described_class::Passageira) }
    end
  end
end
