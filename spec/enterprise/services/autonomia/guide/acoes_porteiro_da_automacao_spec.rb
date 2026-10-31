require 'rails_helper'

# #2414 F1.3 (D2/D4): o Guia só monta ou liga automação para quem tem `automation_manage`. Com a função
# personalizada que dá a chave, funciona sem ser admin; sem ela, a pessoa ouve que não tem acesso. Automação de etapa
# do CRM pede também `crm_manage_pipelines`, no Guia e na tela.
RSpec.describe Autonomia::Guide::Acoes do
  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:stage) { create_crm_pipeline(account: account, user: admin).last }

  before { account.labels.create!(title: 'lead') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def com_funcao(permissions)
    user, account_user = create_crm_agent(account: account, name: 'Juliana Prado')
    account_user.update!(custom_role: CustomRole.create!(account: account, name: "Função #{SecureRandom.hex(4)}",
                                                         permissions: permissions))
    user
  end

  def para(user)
    described_class.new(account: account, user: user)
  end

  def regra
    { name: 'Lead novo vai para o Rafael', event_name: 'conversation_created', active: false,
      conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }],
      actions: [{ action_name: 'add_label', action_params: ['lead'] }] }
  end

  it 'sem automation_manage, o pedido de criar automação ouve que não tem acesso' do
    sem_chave = com_funcao(%w[conversation_manage])

    expect { para(sem_chave).executar('POST automation_rules', { corpo: regra }) }
      .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.automation_manage_only'))
  end

  it 'com automation_manage, cria a automação sem ser admin' do
    com_chave = com_funcao(%w[automation_view automation_manage])

    resultado = nil
    expect { resultado = para(com_chave).executar('POST automation_rules', { corpo: regra }) }.to change(AutomationRule, :count).by(1)
    expect(resultado.ok).to be(true)
  end

  it 'automation_manage não abre o resto do catálogo' do
    com_chave = com_funcao(%w[automation_view automation_manage])

    expect { para(com_chave).executar('POST labels', { corpo: { title: 'x' } }) }
      .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.admin_only'))
  end

  it 'o ensaio só lê: basta ver as regras (automation_view), como na tela' do
    so_ve = com_funcao(%w[automation_view])
    regra_gravada = create(:automation_rule, account: account)

    expect { para(so_ve).conferir!('POST automation_rules/:id/ensaio', { caminho: { id: regra_gravada.id }, corpo: {} }) }
      .not_to raise_error
    expect { para(so_ve).executar('POST automation_rules', { corpo: regra }) }
      .to raise_error(described_class::Recusada, I18n.t('autonomia.guide.automation_manage_only'))
  end

  it 'o Decisor segue a mesma chave: com automation_manage o Guia deixa passar' do
    com_chave = com_funcao(%w[automation_view automation_manage])

    expect(Autonomia::Guide::PorteiroDaAutomacao.recusa('POST autonomia/decisores', account.account_users.find_by(user: com_chave)))
      .to be_nil
    expect(Autonomia::Guide::PorteiroDaAutomacao.recusa('POST autonomia/decisores', account.account_users.find_by(user: com_funcao([]))))
      .to eq('automation_manage_only')
  end

  # A cópia nasce ligada (o `active` vem junto), então passa a agir sozinha: o Guia pede confirmação.
  it 'copiar regra pede confirmação, para qualquer perfil' do
    expect(para(admin).desfazivel?('POST automation_rules/:automation_rule_id/clone')).to be(false)
  end

  describe 'automação de etapa do CRM' do
    def etapa_pelo_guia(user)
      para(user).executar('POST crm/stages/:stage_id/stage_automations',
                          { caminho: { stage_id: stage.id }, corpo: { stage_automation: { name: 'Entrou', trigger_event: 'on_enter' } } })
    end

    it 'só com crm_manage_pipelines, o Guia recusa' do
      expect { etapa_pelo_guia(com_funcao(%w[crm_manage_pipelines])) }.to raise_error(described_class::Recusada)
    end

    it 'só com automation_manage, a plataforma recusa (falta a chave do funil)' do
      resultado = etapa_pelo_guia(com_funcao(%w[automation_view automation_manage]))

      expect(resultado.ok).to be(false)
      expect(account.crm_stage_automations.count).to eq(0)
    end

    def politicas(user)
      account_user = account.account_users.find_by(user: user)
      contexto = { account: account, user: user, account_user: account_user }
      automacao = account.crm_stage_automations.new(account: account)
      [Crm::StageAutomationPolicy.new(contexto, Crm::StageAutomation).create?,
       Crm::StageAutomationPolicy.new(contexto, automacao).update?,
       Crm::StageAutomationStepPolicy.new(contexto, Crm::StageAutomationStep).create?]
    end

    it 'na tela também: só com crm_manage_pipelines não monta, nem o passo; com as duas, monta' do
      expect(politicas(com_funcao(%w[crm_manage_pipelines]))).to eq([false, false, false])
      expect(politicas(com_funcao(%w[crm_manage_pipelines automation_manage]))).to eq([true, true, true])
    end

    it 'com as duas chaves, cria' do
      resultado = etapa_pelo_guia(com_funcao(%w[automation_view automation_manage crm_manage_pipelines]))

      expect(resultado.ok).to be(true)
      expect(account.crm_stage_automations.count).to eq(1)
    end
  end
end
