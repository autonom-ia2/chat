require 'rails_helper'

# #1593 — a marca de segurar depois de um erro na passagem do robô ao agente de IA. Cada cenário diz que falha pega.
RSpec.describe Crm::SegurarNaFilaJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil, status: :open) }

  # Pega: a conversa esperando pessoa sem a marca do motor (a fila não a via).
  it 'marca a conversa que espera pessoa, com o motivo e a falha' do
    described_class.perform_now(conversation.id, 'robo_pediu')

    expect(Crm::Entrega::Marca.dados(conversation.reload)).to include('modo' => 'segurando', 'motivo' => 'robo_pediu',
                                                                      'falha' => 'erro_na_passagem')
  end

  # Pega: a marca por cima de quem já assumiu (a fila tiraria a conversa dela).
  it 'quem entrou nesse meio tempo vence: com pessoa no nome, nada é gravado' do
    conversation.update!(assignee: agente)

    described_class.perform_now(conversation.id, 'robo_pediu')

    expect(Crm::Entrega::Marca.presente?(conversation.reload)).to be(false)
  end

  # Pega: a falha ao marcar engolida (a conversa ficava esperando pessoa para sempre).
  it 'falhou ao marcar: agenda nova tentativa, que marca depois', :aggregate_failures do
    chamadas = 0
    allow(Crm::Entrega::Marca).to receive(:marcar).and_wrap_original do |original, *args, **opcoes|
      chamadas += 1
      raise ActiveRecord::LockWaitTimeout if chamadas == 1

      original.call(*args, **opcoes)
    end

    described_class.perform_now(conversation.id, 'robo_pediu')

    expect(described_class).to have_been_enqueued.with(conversation.id, 'robo_pediu')
    perform_enqueued_jobs
    expect(Crm::Entrega::Marca.presente?(conversation.reload)).to be(true)
  end

  # Pega: token ou documento indo para o log junto da mensagem do erro.
  it 'o erro no log: classe, mensagem sem segredo e onde estourou', :aggregate_failures do
    erro = RuntimeError.new("falhou com chave #{'a' * 40} e cpf 12345678901")
    erro.set_backtrace(['app/services/x.rb:10:in `y`'])

    linha = described_class.para_log(erro)

    expect(linha).to include('erro=RuntimeError', '<REDACTED>', 'onde=app/services/x.rb:10')
    expect(linha).not_to include('a' * 40, '12345678901')
  end
end
