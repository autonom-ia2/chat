require 'rails_helper'

RSpec.describe Autonomia::Agents::ToolRun do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:other_conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  def open_run(slug: 'consultar_cotacao', conversation_id: conversation.id, arguments: { placa: 'ABC1D23' },
               origin_message_id: 4242)
    described_class.open!(agent: agent, slug: slug, arguments: arguments,
                          scope: { conversation_id: conversation_id, agent_inbox_id: agent_inbox.id,
                                   origin_message_id: origin_message_id })
  end

  def promote(run, expires_at: 2.minutes.from_now)
    run.promote!(expected_chunks: 2, notify_customer: false, expires_at: expires_at)
    run
  end

  describe '.open!' do
    it 'creates a pending run with a unique execution key and stringified arguments' do
      # Arrange / Act
      run = open_run(arguments: { placa: 'ABC1D23', condutor: { ano_nascimento: 1985 } })
      other = open_run(conversation_id: other_conversation.id)

      # Assert
      expect(run).to have_attributes(status: 'pending', slug: 'consultar_cotacao', account_id: account.id,
                                     conversation_id: conversation.id, agent_inbox_id: agent_inbox.id,
                                     autonomia_agent_id: agent.id, sequence: 0, attempts: 0)
      expect(run.arguments).to eq('placa' => 'ABC1D23', 'condutor' => { 'ano_nascimento' => 1985 })
      expect(run.execution_key).to be_present
      expect(other.execution_key).not_to eq(run.execution_key)
    end

    it 'supersedes the live run of the same conversation and tool, keeping exactly one active' do
      # Arrange
      first = open_run

      # Act
      second = open_run

      # Assert
      expect(first.reload.status).to eq('superseded')
      expect(second.status).to eq('pending')
      expect(described_class.active.for_conversation(conversation.id).pluck(:id)).to eq([second.id])
    end

    it 'lets the database reject a second active run for the same conversation and tool' do
      # Arrange
      open_run

      # Act / Assert — o índice único parcial é quem garante, não o supersede da aplicação
      expect do
        described_class.create!(account: account, agent: agent, conversation_id: conversation.id,
                                agent_inbox_id: agent_inbox.id, slug: 'consultar_cotacao',
                                status: 'running', execution_key: SecureRandom.uuid, arguments: {})
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'keeps runs of different tools alive side by side in the same conversation' do
      # Arrange / Act
      cotacao = open_run(slug: 'consultar_cotacao')
      apolice = open_run(slug: 'consultar_apolice')

      # Assert
      expect(cotacao.reload.status).to eq('pending')
      expect(apolice.status).to eq('pending')
      expect(described_class.active.for_conversation(conversation.id).pluck(:slug))
        .to contain_exactly('consultar_cotacao', 'consultar_apolice')
    end

    it 'returns nil instead of lying to the model when the unique index rejects the insert' do
      # Arrange — sem o supersede, a segunda abertura colide no índice único parcial
      open_run
      allow(described_class).to receive(:active).and_return(described_class.none)

      # Act
      collided = open_run

      # Assert
      expect(collided).to be_nil
    end
  end

  describe '#promote!' do
    it 'moves the run out of pending only once and records the dispatch metadata' do
      # Arrange
      run = open_run
      deadline = 90.seconds.from_now

      # Act
      first_call = run.promote!(expected_chunks: 3,
                                notify_customer: true, expires_at: deadline)
      second_call = run.promote!(expected_chunks: 7,
                                 notify_customer: false, expires_at: 1.hour.from_now)

      # Assert
      expect(first_call).to be(true)
      expect(second_call).to be(false)
      expect(run.reload).to have_attributes(status: 'running', origin_message_id: 4242,
                                            expected_chunks: 3, notify_customer: true)
      expect(run.expires_at).to be_within(1.second).of(deadline)
    end
  end

  describe '#discard!' do
    it 'discards a run that never ran' do
      # Arrange
      run = open_run

      # Act / Assert
      expect(run.discard!).to be(true)
      expect(run.status).to eq('discarded')
    end

    it 'refuses to discard a run that is already running' do
      # Arrange
      run = promote(open_run)

      # Act / Assert
      expect(run.discard!).to be(false)
      expect(run.reload.status).to eq('running')
    end
  end

  describe '#finish!' do
    it 'finishes a running run and stores the failure code' do
      # Arrange
      run = promote(open_run)

      # Act / Assert
      expect(run.finish!('failed', failure_code: 'deadline')).to be(true)
      expect(run).to have_attributes(status: 'failed', failure_code: 'deadline')
    end

    it 'refuses to finish a run that was never promoted' do
      # Arrange
      run = open_run

      # Act / Assert
      expect(run.finish!('done')).to be(false)
      expect(run.reload.status).to eq('pending')
    end
  end

  describe '#advance_sequence!' do
    it 'advances only for the publisher holding the current sequence' do
      # Arrange
      run = promote(open_run)

      # Act
      winner = run.advance_sequence!(0)
      loser = run.advance_sequence!(0)

      # Assert
      expect(winner).to be(true)
      expect(loser).to be(false)
      expect(run.sequence).to eq(1)
      expect(run.reload.sequence).to eq(1)
    end
  end

  describe '#expired?' do
    it 'is false while there is no deadline' do
      # Arrange / Act / Assert
      expect(open_run.expired?).to be(false)
    end

    it 'is false while the deadline is in the future' do
      # Arrange
      run = promote(open_run, expires_at: 90.seconds.from_now)

      # Act / Assert
      expect(run.expired?).to be(false)
    end

    it 'is true once the deadline is in the past' do
      # Arrange
      run = promote(open_run, expires_at: 1.second.ago)

      # Act / Assert
      expect(run.expired?).to be(true)
    end
  end

  # O token vem do CONTEÚDO, não da posição: uma consulta que reemita a mesma entrega tem de bater
  # com a mensagem já publicada, mesmo que a sequência tenha andado.
  describe '#delivery_token' do
    it 'derives the token from the text and ignores the sequence' do
      # Arrange
      run = promote(open_run)
      token = run.delivery_token('Encontrei 3 opções')

      # Act
      run.advance_sequence!(0)

      # Assert
      expect(token).to start_with("#{run.execution_key}:")
      expect(run.delivery_token('Encontrei 3 opções')).to eq(token)
      expect(run.delivery_token('outro texto')).not_to eq(token)
    end
  end

  describe '#record_delivery!' do
    it 'counts only tool deliveries, so the outcome knows whether the customer got a result' do
      # Arrange
      run = promote(open_run)

      # Act
      run.record_delivery!
      run.advance_sequence!(run.sequence)

      # Assert — a mensagem publicada moveu a sequência, mas só a ENTREGA move o contador
      expect(run.reload).to have_attributes(delivered_count: 1, sequence: 1)
    end
  end

  describe '#dead?' do
    it 'is true only for statuses that must never publish again' do
      # Arrange
      run = open_run

      # Act / Assert
      expect(run).not_to be_dead
      run.update!(status: 'superseded')
      expect(run).to be_dead
      run.update!(status: 'done')
      expect(run).not_to be_dead
    end
  end
end
