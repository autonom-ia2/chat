require 'rails_helper'

# A fila do motor de entrega no HandoffDrainJob (#1454): rodada limitada, cursor no Redis que volta ao começo, e o job
# não para quando o Redis não responde.
RSpec.describe Crm::Ai::HandoffDrainJob do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:cursor_key) { described_class::CURSOR_KEY }

  before do
    stub_const("#{described_class}::CONVERSAS_POR_RODADA", 2)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    create(:inbox_member, inbox: inbox, user: ana)
    Redis::Alfred.delete(cursor_key)
    online
  end

  after { Redis::Alfred.delete(cursor_key) }

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  # Três conversas seguras pelo motor (ninguém online na passagem).
  def tres_seguras
    Array.new(3) do
      conversation = create(:conversation, account: account, inbox: inbox, status: :open).reload
      conversation.update!(ai_assignee: bot, assignee: nil)
      conversation.bot_handoff!
      conversation.reload
    end
  end

  it 'trata no máximo uma rodada, grava o cursor e, na rodada seguinte, termina e volta ao começo', :aggregate_failures do
    primeira, segunda, terceira = tres_seguras
    online(ana)

    described_class.perform_now
    expect([primeira, segunda].map { |c| c.reload.assignee_id }).to eq([ana.id, ana.id])
    expect(terceira.reload.assignee_id).to be_nil
    expect(Redis::Alfred.get(cursor_key).to_i).to eq(segunda.id)

    described_class.perform_now
    expect(terceira.reload.assignee_id).to eq(ana.id)
    expect(Redis::Alfred.get(cursor_key).to_i).to eq(0)
  end

  it 'lê a presença de cada conta uma vez só por rodada' do
    tres_seguras
    expect(OnlineStatusTracker).to receive(:get_available_users).with(account.id).once.and_return({})

    described_class.perform_now
  end

  it 'com o teto de tempo estourado, para e grava onde parou', :aggregate_failures do
    primeira, = tres_seguras
    online(ana)
    stub_const("#{described_class}::TEMPO_MAXIMO_DA_RODADA", -1)

    described_class.perform_now

    expect(primeira.reload.assignee_id).to be_nil
    expect(Redis::Alfred.get(cursor_key).to_i).to eq(0)
  end

  it 'sem Redis para ler o cursor: começa do início, loga e segue', :aggregate_failures do
    primeira, = tres_seguras
    online(ana)
    allow(Redis::Alfred).to receive(:get).and_call_original
    allow(Redis::Alfred).to receive(:get).with(cursor_key).and_raise(Redis::CannotConnectError)
    allow(Rails.logger).to receive(:error).and_call_original

    expect { described_class.perform_now }.not_to raise_error

    expect(primeira.reload.assignee_id).to eq(ana.id)
    expect(Rails.logger).to have_received(:error).with(/cursor indisponível/)
  end

  it 'sem Redis para gravar o cursor: loga e não derruba o job (os cards do CRM ainda rodam)', :aggregate_failures do
    primeira, = tres_seguras
    online(ana)
    allow(Redis::Alfred).to receive(:set).and_call_original
    allow(Redis::Alfred).to receive(:set).with(cursor_key, anything).and_raise(Redis::CannotConnectError)
    allow(Rails.logger).to receive(:error).and_call_original
    allow(Crm::Pipeline).to receive(:active).and_call_original

    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { described_class.perform_now }

    expect(primeira.reload.assignee_id).to eq(ana.id)
    expect(Rails.logger).to have_received(:error).with(/cursor não gravado/)
    expect(Crm::Pipeline).to have_received(:active)
  end
end
