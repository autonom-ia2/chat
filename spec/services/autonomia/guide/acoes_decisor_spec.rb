require 'rails_helper'

# #858 — "a automação com Decisor só liga depois que a pessoa aprova o teste" é garantido aqui, não no
# texto do manual: deixar ligada uma regra com Decisor não tem desfazer (a regra já agiu) e pede confirmação.
RSpec.describe Autonomia::Guide::Acoes do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:decisor) { create(:autonomia_decisor, account: conta) }
  let(:passos) do
    [{ action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] }, { action_name: 'add_label', action_params: ['lead'] }]
  end
  let(:acoes) { described_class.new(account: conta, user: admin) }

  def corpo(**campos)
    { descricao: 'Regra do lead.', corpo: { name: 'Lead', event_name: 'message_created', actions: passos }.merge(campos) }
  end

  it 'criar a regra com Decisor desligada continua direto, com desfazer' do
    expect(acoes.desfazivel?('POST automation_rules', corpo(active: false))).to be(true)
  end

  it 'criar a regra com Decisor ligada, ou sem dizer (nasce ligada), pede confirmação' do
    expect(acoes.desfazivel?('POST automation_rules', corpo(active: true))).to be(false)
    expect(acoes.desfazivel?('POST automation_rules', corpo)).to be(false)
    expect { acoes.conferir!('POST automation_rules', corpo) }.to raise_error(described_class::Recusada)
  end

  it 'ligar uma regra que tem Decisor pede confirmação; ligar regra sem Decisor não' do
    com_decisor = create(:automation_rule, account: conta, active: false, actions: passos)
    sem_decisor = create(:automation_rule, account: conta, active: false)

    expect(acoes.desfazivel?('PATCH automation_rules/:id', { caminho: { id: com_decisor.id }, corpo: { active: true } })).to be(false)
    expect(acoes.desfazivel?('PATCH automation_rules/:id', { caminho: { id: sem_decisor.id }, corpo: { active: true } })).to be(true)
  end

  # #3106 (revisão do Codex): o PUT cai no mesmo update, e o corpo embrulhado chega aberto à plataforma.
  it 'ligar por PUT, ou com o corpo embrulhado, também pede confirmação' do
    com_decisor = create(:automation_rule, account: conta, active: false, actions: passos)
    caminho = { id: com_decisor.id }

    expect(acoes.desfazivel?('PUT automation_rules/:id', { caminho: caminho, corpo: { active: true } })).to be(false)
    expect(acoes.desfazivel?('PATCH automation_rules/:id', { caminho: caminho, corpo: { automation_rule: { active: true } } })).to be(false)
    expect { acoes.conferir!('PUT automation_rules/:id', { caminho: caminho, corpo: { active: true } }) }
      .to raise_error(described_class::Recusada)
  end

  # #3106 (revisão do Codex): ligar a regra gravada que manda mensagem, sem repetir as ações, também confirma.
  it 'ligar regra gravada que manda mensagem pede confirmação; renomear a que já está ligada segue direto' do
    acoes_que_mandam = [{ 'action_name' => 'send_message', 'action_params' => ['Olá! Já vamos te atender.'] }]
    desligada = create(:automation_rule, account: conta, active: false, actions: acoes_que_mandam)
    ligada = create(:automation_rule, account: conta, active: true, actions: acoes_que_mandam)

    expect(acoes.desfazivel?('PATCH automation_rules/:id', { caminho: { id: desligada.id }, corpo: { active: true } })).to be(false)
    expect(acoes.desfazivel?('PUT automation_rules/:id', { caminho: { id: desligada.id }, corpo: { automation_rule: { active: true } } }))
      .to be(false)
    expect(acoes.desfazivel?('PATCH automation_rules/:id', { caminho: { id: ligada.id }, corpo: { name: 'Boas-vindas' } })).to be(true)
  end

  it 'pôr o Decisor numa regra que já está ligada pede confirmação' do
    ligada = create(:automation_rule, account: conta, active: true)

    expect(acoes.desfazivel?('PATCH automation_rules/:id', { caminho: { id: ligada.id }, corpo: { actions: passos } })).to be(false)
  end

  it 'regra sem Decisor segue o caminho de sempre' do
    dados = { descricao: 'Regra.', corpo: { name: 'X', actions: [{ action_name: 'add_label', action_params: ['x'] }] } }

    expect(acoes.desfazivel?('POST automation_rules', dados)).to be(true)
  end
end
