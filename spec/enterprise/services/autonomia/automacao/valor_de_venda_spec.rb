require 'rails_helper'

# #2597 (funções personalizadas, #1784): a Automação livre lê `card.valor` com a mesma regra do resto do CRM
# (Crm::ValorDeVenda.ve?, chave `sales_value_view`). Quem salva sem a chave não grava receita que leia o valor; a
# automação cujo dono perdeu a chave lê vazio e não escreve nem manda o valor. Administrador e agente sem função seguem
# vendo. Fica em spec/enterprise: a metade de função personalizada é EE.
RSpec.describe 'Automação livre: valor da venda com sales_value_view (#2597)', :aggregate_failures, :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:funil) { funil_e_etapa.first }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: funil_e_etapa.last, title: 'Pedido', currency: 'BRL', value_cents: 250_000,
                              inbox: conversa.inbox, primary_conversation: conversa, contact: conversa.contact)
  end
  let(:gatilho) { { 'tipo' => 'card.ganho', 'funil_id' => funil.id } }
  let(:valor) { { '$valor' => 'card.valor' } }
  let(:caro) do
    { 'id' => 's1', 'tipo' => 'se', 'condicao' => { 'campo' => valor, 'op' => 'maior', 'valor' => 1000 },
      'entao' => [prioridade_passo('a1', 'high')], 'senao' => [prioridade_passo('a2', 'low')] }
  end

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_gatilhos')
  end

  after { Current.reset }

  def base = %w[automation_manage crm_manage_pipelines crm_view crm_manage_cards conversation_manage contact_manage]

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: conversa.inbox)
    user
  end

  def receita(passos) = { 'gatilho' => gatilho, 'passos' => passos }

  def na_conta(user) = AccountUser.find_by(account: account, user: user)

  def problemas(passos, quem, gatilho_da_receita = gatilho)
    completa = receita(passos).merge('gatilho' => gatilho_da_receita)
    Autonomia::Automacao::Receita.new(completa, conta: account, account_user: na_conta(quem)).problemas
  end

  def recusa?(lista, passo)
    lista.include?(I18n.t('autonomia.automacao.receita.valor_de_venda', passo: passo, caminho: 'card.valor'))
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def rodar(definicao)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: card, chave_gatilho: 'card.ganho').call
    end
    definicao.execucoes.order(:id).last
  end

  describe 'salvar' do
    let(:sem_chave) { pessoa_com(base) }
    let(:com_chave) { pessoa_com(base + %w[sales_value_view]) }
    let(:no_texto) { [mensagem_passo('m1', 'Valor: ', valor)] }

    it 'recusa ler o valor no texto, na condição, no filtro do gatilho e no caminho da ação para quem não tem a chave' do
      no_filtro = { 'campo' => valor, 'op' => 'maior', 'valor' => 0 }
      no_caminho = prioridade_passo('a1', conversa_id: valor)

      expect(recusa?(problemas(no_texto, sem_chave), 'm1')).to be(true)
      expect(recusa?(problemas([caro], sem_chave), 's1')).to be(true)
      expect(recusa?(problemas(no_texto, sem_chave, gatilho.merge('filtros' => [no_filtro])), 'gatilho')).to be(true)
      expect(recusa?(problemas([no_caminho], sem_chave), 'a1')).to be(true)
    end

    it 'deixa quem tem a chave, o administrador e o agente sem função' do
      sem_funcao = create(:user, account: account, role: :agent)

      [com_chave, admin, sem_funcao].each { |quem| expect(recusa?(problemas(no_texto, quem), 'm1')).to be(false) }
    end

    it 'o dono do card sem a chave também não lê o valor pela automação (ve?, não ve_o_card?)' do
      card.update!(owner: sem_chave)

      expect(recusa?(problemas(no_texto, sem_chave), 'm1')).to be(true)
    end

    it 'o salvar da versão confere o autor' do
      definicao = create(:autonomia_automacao, account: account, ligada_por: sem_chave)

      expect { definicao.salvar_versao!(receita: receita(no_texto), autor: sem_chave) }.to raise_error(ActiveRecord::RecordInvalid, /card\.valor/)
      expect { definicao.salvar_versao!(receita: receita(no_texto), autor: com_chave) }.not_to raise_error
    end

    it 'religar ("assumir e religar") confere quem liga' do
      definicao = automacao_ligada(account, com_chave, [caro], gatilho: gatilho)
      definicao.update!(ativa: false)

      recusa = definicao.assumir_e_religar!(sem_chave, versao_id: definicao.versao_ativa_id)
      expect([recusa&.motivo, recusa?(Array(recusa&.problemas), 's1')]).to eq(['receita_com_problema', true])
    end
  end

  describe 'ler' do
    let(:sem_chave) { pessoa_com(base) }
    let(:com_chave) { pessoa_com(base + %w[sales_value_view]) }

    def ler(quem) = Autonomia::Automacao::Valores.new(alvo: card, quem: quem).ler('card.valor')

    it 'só lê o valor para quem vê valores de venda; sem quem, lê vazio' do
      card.update!(owner: sem_chave)

      expect([ler(com_chave), ler(admin), ler(sem_chave), ler(nil)]).to eq([2500, 2500, nil, nil])
    end

    it 'quem não está na conta (saiu, ou é de outra) lê vazio' do
      de_fora = create(:user)

      expect(ler(de_fora)).to be_nil
    end

    it 'os outros campos do card não mudam' do
      expect(Autonomia::Automacao::Valores.new(alvo: card, quem: sem_chave).ler('card.titulo')).to eq('Pedido')
    end
  end

  describe 'rodar' do
    let(:dono) { pessoa_com(base + %w[sales_value_view]) }

    def tirar_a_chave
      AccountUser.find_by(account: account, user: dono).custom_role.update!(permissions: base)
    end

    it 'com a chave, a condição lê o valor' do
      execucao = rodar(automacao_ligada(account, dono, [caro], gatilho: gatilho))

      expect([conversa.reload.priority, registros(execucao).map(&:first)]).to eq(['high', %w[s1 a1]])
    end

    it 'quem ligou perdeu a chave: a condição vê vazio e a mensagem pula, sem escrever nem mandar o valor' do
      definicao = automacao_ligada(account, dono, [caro, mensagem_passo('m1', 'Valor: ', valor)], gatilho: gatilho)
      tirar_a_chave

      execucao = rodar(definicao)

      expect(conversa.reload.priority).to eq('low')
      expect(registros(execucao)).to eq([['s1', 'ok', nil], ['a2', 'ok', nil], %w[m1 pulado faltou_valor]])
      expect(conversa.messages.where('content LIKE ?', 'Valor:%')).to be_empty
    end

    # Sem account_user, o Valores já lê vazio (ver "quem não está na conta"); antes disso, a execução nem anda.
    it 'quem ligou saiu da conta: a execução não anda, nada escrito nem mandado' do
      definicao = automacao_ligada(account, dono, [caro, mensagem_passo('m1', 'Valor: ', valor)], gatilho: gatilho)
      AccountUser.find_by(account: account, user: dono).destroy!

      execucao = rodar(definicao)

      expect(registros(execucao)).to eq([%w[inicio pulado quem_ligou_saiu_da_conta]])
      expect(conversa.reload.priority).to be_nil
      expect(conversa.messages.where('content LIKE ?', 'Valor:%')).to be_empty
    end
  end
end
