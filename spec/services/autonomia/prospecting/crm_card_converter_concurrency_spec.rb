require 'rails_helper'
require 'timeout'

# O mesmo lead enviado duas vezes ao mesmo tempo (duplo clique, duas abas, Listas e busca juntas), em duas conexões de
# verdade e sem a transação do teste por fora (#680). Os dois envios passam juntos pela conferência de "já tem card";
# quem chega depois espera a trava do lead, vê o card do outro e devolve "já existente", nunca uma falha.
RSpec.describe Autonomia::Prospecting::CrmCardConverter do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:user) { create(:user, :administrator, account: account) }
  let!(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let!(:lead) do
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/corrida',
                                         name: 'Padaria Corrida', phone: '+55 31 99111-2222', country: 'BR')
  end
  let(:workers) { [] }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    automation = account.crm_stage_automations.create!(
      pipeline: pipeline, stage: stage, name: 'Entrada prospecção', trigger_event: :on_enter, created_by: user
    )
    # Passo inofensivo: só uma tarefa de lembrete, nenhuma mensagem ao cliente.
    automation.steps.create!(
      account: account, position: 0, delay_seconds: 0, action_type: :create_follow_up,
      action_config: { title: 'Ligar para o decisor', automation_mode: 'reminder_only' }
    )
  end

  after do
    workers.each { |worker| worker.join(1) || worker.kill.join }
    # Sem a transação do teste, a limpeza é explícita e na ordem das chaves: o card leva junto atividades, tarefas e
    # execuções; depois a automação, o funil, contato, empresa, a conta e o usuário.
    [Crm::Card, Crm::Activity, Crm::StageAutomationStep, Crm::StageAutomation, Crm::PipelineStage, Crm::Pipeline,
     Autonomia::Prospecting::Lead, Contact, Company].each do |model|
      model.where(account_id: account.id).delete_all
    end
    account.reload.destroy!
    user.reload.destroy!
  end

  def barrier(parties, wait_seconds)
    mutex = Mutex.new
    arrived = ConditionVariable.new
    count = 0
    lambda do
      mutex.synchronize do
        count += 1
        arrived.broadcast
        deadline = Time.current + wait_seconds
        arrived.wait(mutex, deadline - Time.current) while count < parties && Time.current < deadline
      end
    end
  end

  # Os dois envios esperam um pelo outro depois da conferência inicial: os dois acham que o lead ainda não tem card.
  def hold_after_first_check(parties)
    wait = barrier(parties, 3)
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:find_stage).and_wrap_original do |original, *args|
      stage_found = original.call(*args)
      wait.call
      stage_found
    end
    # rubocop:enable RSpec/AnyInstance
  end

  def send_twice
    hold_after_first_check(2)
    results = Queue.new
    2.times do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          results << Autonomia::Prospecting::CrmCardBatch.new(
            account: account, user: user, lead_ids: [lead.id], pipeline_id: pipeline.id, stage_id: stage.id
          ).perform
        end
      rescue StandardError => e
        results << e
      end
    end
    Timeout.timeout(15) { workers.each(&:join) }
    Array.new(2) { results.pop }
  end

  it 'um envio cria, o outro devolve o mesmo card como já existente, e a automação roda uma vez' do
    outcomes = send_twice

    expect(outcomes).to all(be_a(Autonomia::Prospecting::CrmCardBatch::Result))
    expect(outcomes.flat_map(&:failed)).to eq([])
    card_id = lead.reload.crm_card_id
    expect(outcomes.flat_map(&:created).map { |row| row[:card_id] }).to eq([card_id])
    expect(outcomes.flat_map(&:existing)).to eq([{ lead_id: lead.id, card_id: card_id }])
    expect(account.crm_cards.count).to eq(1)
    expect(Crm::StageAutomationExecution.where(card_id: card_id).count).to eq(1)
  end
end
