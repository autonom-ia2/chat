require 'rails_helper'

# #858 etapa 2 — o passo "Perguntar ao Decisor" nas automações de etapa do CRM, com o card como alvo.
# Mesmo contrato da regra de automação: segue só na chave combinada, dúvida vai ao Guia, a retomada roda
# os passos uma vez só e confere de novo se o card ainda está onde a automação o pegou.
RSpec.describe Autonomia::Decisores::PerguntarEtapaJob do
  include ActiveJob::TestHelper

  let(:conta_e_admin) { create_account_and_user }
  let(:account) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:pipeline_e_novo) { create_crm_pipeline(account: account, user: admin) }
  let(:proposta) { create_crm_stage(account: account, pipeline: pipeline_e_novo.first, name: 'Proposta') }
  let(:contact) { create(:contact, account: account, name: 'Carlos Frota', email: 'carlos@xpto.com.br') }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_e_novo.first, stage: pipeline_e_novo.last, contact: contact, title: 'Frota da XPTO, 40 carros')
  end
  let(:decisor) { create(:autonomia_decisor, account: account, pergunta: 'É empresa grande?', leituras: %w[card contato empresa]) }
  let!(:automacao) do
    automacao = account.crm_stage_automations.create!(pipeline: proposta.pipeline, stage: proposta, name: 'Grande', trigger_event: :on_enter)
    automacao.steps.create!(account: account, position: 0, action_type: :perguntar_ao_decisor,
                            action_config: { decisor_id: decisor.id, chave_que_segue: 'sim' })
    automacao.steps.create!(account: account, position: 1, action_type: :create_follow_up, action_config: { title: 'Ligar para a frota' })
    automacao
  end
  let(:jev_url) { 'https://api.typesafe.ai/v1/systemone' }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    allow(TypesafeAi::Config).to receive_messages(api_key: 'ts_test_key_not_real', model: 'jev-1.13.0')
  end

  def jev_responde(choice, confidence)
    stub_request(:post, jev_url).to_return(
      status: 200,
      body: { model: 'jev-1.13.0', usage: { input_tokens: 600, output_tokens: 2 },
              answers: { decisao: { type: 'choice', choice: choice, confidence: confidence } } }.to_json
    )
  end

  def mover_para_proposta
    card.update!(stage: proposta)
    Crm::StageAutomations::Runner.new(card: card, actor: admin, from_stage_id: pipeline_e_novo.last.id, to_stage_id: proposta.id).perform
  end

  def execucao
    account.crm_stage_automation_executions.find_by(stage_automation: automacao)
  end

  # MOTIVO: o Jev não pode rodar dentro da requisição que move o card; os passos seguintes esperam por ele.
  it 'mover o card não roda os passos depois do Decisor: o passo vai para um job e a execução espera' do
    expect { mover_para_proposta }.to have_enqueued_job(described_class)

    expect(account.crm_follow_ups.count).to eq(0)
    expect(execucao).to be_running
    expect(execucao.metadata['decisor']).to include('step_id' => automacao.steps.first.id)
  end

  it 'segue para os passos seguintes quando o Decisor responde a chave, lendo o card e nunca o e-mail' do
    jev_responde('sim', 0.93)

    perform_enqueued_jobs(only: described_class) { mover_para_proposta }

    expect(account.crm_follow_ups.pluck(:title)).to eq(['Ligar para a frota'])
    expect(execucao.reload).to be_completed
    expect(Autonomia::DecisorDecisao.last).to have_attributes(crm_card_id: card.id, gatilho: execucao.trigger_token, status: 'decidida')
    expect(a_request(:post, jev_url).with { |req| req.body.include?('Frota da XPTO') && req.body.exclude?('carlos@xpto') }).to have_been_made
  end

  it 'para quando a resposta é outra, e a execução termina' do
    jev_responde('nao', 0.95)

    perform_enqueued_jobs(only: described_class) { mover_para_proposta }

    expect(account.crm_follow_ups.count).to eq(0)
    expect(execucao.reload).to be_completed
    expect(execucao.metadata['step_results'].last['payload']).to include('resposta' => 'nao', 'parou' => true)
  end

  # MOTIVO: um novo disparo com o mesmo gatilho não pode rodar de novo os passos de uma execução que espera.
  it 'enquanto espera o Decisor, um novo disparo da mesma entrada não roda nada' do
    mover_para_proposta
    clear_enqueued_jobs

    expect do
      Crm::StageAutomations::Runner.new(card: card, actor: admin, from_stage_id: pipeline_e_novo.last.id, to_stage_id: proposta.id).perform
    end.not_to have_enqueued_job(described_class)
  end

  context 'with dúvida resolvida depois' do
    before do
      jev_responde('sim', 0.55)
      perform_enqueued_jobs(only: described_class) { mover_para_proposta }
    end

    let(:decisao) { Autonomia::DecisorDecisao.last }

    def resolver
      perform_enqueued_jobs(only: described_class) do
        Autonomia::Decisores::Resolucao.new(decisao: decisao.reload, user: admin).resolver!('sim')
      end
    end

    it 'na dúvida não segue, manda ao Guia e, resolvida, roda os passos uma vez só' do
      expect(decisao.status).to eq('duvida')
      expect(Autonomia::Decisores::DuvidaJob).to have_been_enqueued.with(decisao.id)
      expect(account.crm_follow_ups.count).to eq(0)

      resolver
      perform_enqueued_jobs(only: described_class) { Autonomia::Decisores::Retomada.enfileirar(decisao.reload) }

      expect(account.crm_follow_ups.count).to eq(1)
      expect(execucao.reload).to be_completed
      expect(decisor.reload.exemplos.last['texto']).to include('Frota da XPTO')
    end

    # MOTIVO: o card saiu da etapa enquanto o caso esperava; agir agora seria fora de hora.
    it 'não retoma quando o card já saiu da etapa' do
      card.update!(stage: pipeline_e_novo.last)

      resolver

      expect(account.crm_follow_ups.count).to eq(0)
      expect(execucao.reload).to be_completed
    end
  end
end
