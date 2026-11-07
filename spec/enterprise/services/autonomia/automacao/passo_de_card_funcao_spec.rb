require 'rails_helper'

# O passo "criar card" (#2414 G4) com quem ligou numa função personalizada: as perguntas da API de cards (criar card,
# `crm_manage_cards`) e a chave de funis (RegraDoFunil.chave?: `crm_manage_pipelines` ou `crm_admin`, decisão do Rodrigo),
# conferidas a cada execução.
# Faltou uma, a automação pausa e nenhum card nasce.
RSpec.describe Autonomia::Automacao::PassoDeCard, :automacao_motor do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Melhorias') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, status: :open).reload }
  let(:base) { %w[automation_manage conversation_manage crm_view] }
  let(:passo) { { 'id' => 'p1', 'tipo' => 'card', 'etapa_id' => etapa.id } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
  end

  after { Current.reset }

  def ligada_por_funcao(permissions)
    pessoa = create(:user, account: account, role: :agent)
    funcao = CustomRole.create!(account: account, name: "Função #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: pessoa).update!(custom_role: funcao)
    inbox.add_members([pessoa.id])
    definicao = automacao_ligada(account, admin, [passo])
    definicao.update_column(:ligada_por_id, pessoa.id) # rubocop:disable Rails/SkipsModelValidations
    definicao.reload
  end

  def executar(definicao)
    execucao = Autonomia::Automacao::Execucao.new(automacao: definicao, account: account)
    acesso = Autonomia::Automacao::Acesso.new(definicao)
    described_class.new(execucao: execucao, passo: passo, alvo: conversa, acesso: acesso).executar
  end

  it 'cria card mas não configura funis: pausa (sem_acesso) e não cria', :aggregate_failures do
    resultado = executar(ligada_por_funcao(base + %w[crm_manage_cards]))

    expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'sem_chave_de_funis'])
    expect(funil.cards).to be_empty
  end

  it 'configura funis mas não cria card: pausa (sem_acesso) e não cria', :aggregate_failures do
    resultado = executar(ligada_por_funcao(base + %w[crm_manage_pipelines]))

    expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'quem_ligou_sem_permissao_card'])
    expect(funil.cards).to be_empty
  end

  it 'com crm_admin, que vale pelas duas chaves: cria o card' do
    expect(executar(ligada_por_funcao(base + %w[crm_admin])).tipo).to eq(:ok)
  end

  it 'com as duas chaves: cria o card', :aggregate_failures do
    resultado = executar(ligada_por_funcao(base + %w[crm_manage_cards crm_manage_pipelines]))

    expect(resultado.tipo).to eq(:ok)
    expect(funil.cards.sole.conversation_id).to eq(conversa.id)
  end

  it 'crm_admin vale pelas duas (como no CrmPermissions)' do
    resultado = executar(ligada_por_funcao(base + %w[crm_admin]))

    expect(resultado.tipo).to eq(:ok)
  end

  describe 'ao salvar e ao ligar (Receita, com a pessoa)' do
    def problemas_de(permissions)
      pessoa = create(:user, account: account, role: :agent)
      funcao = CustomRole.create!(account: account, name: "Função #{SecureRandom.hex(4)}", permissions: permissions)
      account_user = AccountUser.find_by(account: account, user: pessoa)
      account_user.update!(custom_role: funcao)
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: account_user).problemas
    end

    it 'configura funis mas não cria card: recusa, em vez de pausar no primeiro disparo' do
      expect(problemas_de(base + %w[crm_manage_pipelines])).to eq([I18n.t('autonomia.automacao.receita.sem_criar_card', passo: 'p1')])
    end

    it 'cria card: aceita (a chave de funis o controller confere)' do
      expect(problemas_de(base + %w[crm_manage_cards crm_manage_pipelines])).to be_empty
    end
  end
end
