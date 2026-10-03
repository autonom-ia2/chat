require 'rails_helper'

# #858 etapa 2 — o Decisor declara o que lê, de uma lista fechada, e o passo só entra numa automação
# cujo gatilho tem aquilo para ler. As recusas ensinam o certo (é com elas que o Guia acerta o corpo).
RSpec.describe Autonomia::Decisor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'aceita leituras da lista e, sem elas, lê as mensagens do cliente como na etapa 1' do
    expect(build(:autonomia_decisor, account: account).leituras_efetivas).to eq(%w[mensagens_recentes])
    expect(build(:autonomia_decisor, account: account, leituras: %w[card empresa])).to be_valid
  end

  # MOTIVO: "telefone" não é uma leitura; a recusa lista o que existe e diz que e-mail/telefone nunca vão.
  it 'recusa o que não está na lista, ensinando o que existe' do
    decisor = build(:autonomia_decisor, account: account, leituras: %w[telefone card])

    expect(decisor).not_to be_valid
    expect(decisor.errors[:leituras].first).to include('telefone cannot be read', 'mensagens_recentes', 'never go to the Jev')
  end

  context 'with o passo numa automação de etapa do CRM' do
    let(:pipeline_e_etapa) { create_crm_pipeline(account: account, user: admin) }
    let(:automacao) do
      pipeline, stage = pipeline_e_etapa
      account.crm_stage_automations.create!(pipeline: pipeline, stage: stage, name: 'Proposta', trigger_event: :on_enter)
    end

    def passo(decisor, chave = 'sim')
      automacao.steps.build(account: account, action_type: :perguntar_ao_decisor,
                            action_config: { decisor_id: decisor&.id, chave_que_segue: chave })
    end

    # MOTIVO: card entrando na etapa não tem mensagem que disparou: ultima_mensagem não teria o que ler.
    it 'recusa o Decisor que lê a mensagem que disparou, dizendo o que dá para ler ali' do
      step = passo(create(:autonomia_decisor, account: account, leituras: %w[ultima_mensagem]))

      expect(step).not_to be_valid
      expect(step.errors[:action_config].first).to include('ultima_mensagem', 'Readable here: mensagens_recentes')
    end

    it 'recusa chave que não é resposta do Decisor e Decisor de outra conta' do
      expect(passo(create(:autonomia_decisor, account: account), 'talvez').tap(&:valid?).errors[:action_config].first)
        .to include('chave_que_segue must be one of: sim, nao')
      expect(passo(create(:autonomia_decisor)).tap(&:valid?).errors[:action_config].first).to include('decisor_id must be a Decisor')
    end

    it 'aceita o Decisor que lê o card' do
      expect(passo(create(:autonomia_decisor, account: account, leituras: %w[card contato]))).to be_valid
    end
  end

  it 'na regra de automação, o gatilho de conversa tem tudo para ler' do
    decisor = create(:autonomia_decisor, account: account, leituras: %w[ultima_mensagem card])
    rule = build(:automation_rule, account: account, event_name: 'message_created',
                                   actions: [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] }])

    expect(rule).to be_valid
  end
end
