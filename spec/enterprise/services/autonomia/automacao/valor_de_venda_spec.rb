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

  # #2780 (decisão 3 do Rodrigo, 09/11): o valor só decide, em qualquer automação; no texto e no corpo, o salvar recusa
  # para todos, com ou sem a chave.
  def so_decide?(lista, passo)
    lista.include?(I18n.t('autonomia.automacao.receita.valor_protegido_so_decide', passo: passo, caminho: 'card.valor'))
  end

  # A versão gravada antes da regra, com o valor num texto ou num corpo: o salvar de hoje a recusaria.
  def versao_antiga(quem, passos)
    definicao = create(:autonomia_automacao, account: account, ligada_por: quem)
    versao = definicao.versoes.new(account: account, numero: 1, autor: quem, digest: SecureRandom.hex(32), receita: receita(passos))
    versao.save!(validate: false)
    definicao.update!(versao_ativa: versao, ativa: true)
    definicao
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

  # O valor calculado no corpo de uma ação (G16): o texto montado lê o valor como o texto da mensagem.
  def no_corpo
    { 'id' => 'a1', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
      'caminho' => { 'id' => { '$valor' => 'conversa.id' } },
      'corpo' => { 'merge' => true, 'custom_attributes' => { 'nota' => { '$texto' => ['Valor ', valor] } } } }
  end

  describe 'salvar' do
    let(:sem_chave) { pessoa_com(base) }
    let(:com_chave) { pessoa_com(base + %w[sales_value_view]) }
    let(:no_texto) { [mensagem_passo('m1', 'Valor: ', valor)] }

    it 'recusa ler o valor na condição, no filtro do gatilho e no caminho da ação para quem não tem a chave' do
      no_filtro = { 'campo' => valor, 'op' => 'maior', 'valor' => 0 }
      no_caminho = prioridade_passo('a1', conversa_id: valor)

      expect(recusa?(problemas([caro], sem_chave), 's1')).to be(true)
      expect(recusa?(problemas([caro], sem_chave, gatilho.merge('filtros' => [no_filtro])), 'gatilho')).to be(true)
      expect(recusa?(problemas([no_caminho], sem_chave), 'a1')).to be(true)
    end

    it 'recusa o valor no texto e no corpo calculado da ação (G16) para todos, com ou sem a chave (#2780)' do
      [sem_chave, com_chave, admin].each do |quem|
        expect([so_decide?(problemas(no_texto, quem), 'm1'), so_decide?(problemas([no_corpo], quem), 'a1')]).to eq([true, true])
      end
    end

    it 'deixa quem tem a chave, o administrador e o agente sem função' do
      sem_funcao = create(:user, account: account, role: :agent)

      [com_chave, admin, sem_funcao].each { |quem| expect(recusa?(problemas([caro], quem), 's1')).to be(false) }
    end

    it 'o dono do card sem a chave também não lê o valor pela automação (ve?, não ve_o_card?)' do
      card.update!(owner: sem_chave)

      expect(recusa?(problemas([caro], sem_chave), 's1')).to be(true)
    end

    it 'o salvar da versão confere o autor' do
      definicao = create(:autonomia_automacao, account: account, ligada_por: sem_chave)

      expect { definicao.salvar_versao!(receita: receita([caro]), autor: sem_chave) }.to raise_error(ActiveRecord::RecordInvalid, /card\.valor/)
      expect { definicao.salvar_versao!(receita: receita([caro]), autor: com_chave) }.not_to raise_error
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

    it 'quem ligou perdeu a chave: a condição vê vazio' do
      definicao = automacao_ligada(account, dono, [caro], gatilho: gatilho)
      tirar_a_chave

      execucao = rodar(definicao)

      expect(conversa.reload.priority).to eq('low')
      expect(registros(execucao)).to eq([['s1', 'ok', nil], ['a2', 'ok', nil]])
    end

    # #2780: a versão antiga com o valor num texto, mesmo de quem tem a chave, não o escreve nem manda.
    it 'versão antiga com a chave: a condição lê o valor e a mensagem com ele pula, sem mandar o valor' do
      execucao = rodar(versao_antiga(dono, [caro, mensagem_passo('m1', 'Valor: ', valor)]))

      expect(conversa.reload.priority).to eq('high')
      expect(registros(execucao)).to eq([['s1', 'ok', nil], ['a1', 'ok', nil], %w[m1 pulado faltou_valor]])
      expect(conversa.messages.where('content LIKE ? OR content LIKE ?', '%2500%', 'Valor:%')).to be_empty
    end

    # G2 (#2601) e #2780: o assunto do e-mail não escreve o valor, como o texto da mensagem.
    it 'versão antiga com a chave: o e-mail com o valor no assunto pula, sem abrir conversa nem mandar o valor' do
      caixa = create(:channel_email, account: account).inbox
      create(:inbox_member, user: dono, inbox: caixa)
      conversa.contact.update!(email: 'cliente@exemplo.com')
      email = { 'id' => 'm1', 'tipo' => 'email', 'caixa_id' => caixa.id, 'assunto' => ['Valor: ', valor], 'texto' => ['Oi'] }

      execucao = rodar(versao_antiga(dono, [email]))

      expect(registros(execucao)).to eq([%w[m1 pulado faltou_valor]])
      expect(caixa.conversations).to be_empty
    end

    it 'versão antiga com o valor calculado do corpo (G16): mesmo com a chave, a ação pula sem gravar o valor' do
      execucao = rodar(versao_antiga(dono, [no_corpo]))

      expect([registros(execucao).map(&:second), conversa.reload.custom_attributes['nota']]).to eq([['pulado'], nil])
    end

    # O "esperar até" (G11) lê a condição com as permissões de quem ligou, como o "se".
    def esperar_caro
      { 'id' => 'e1', 'tipo' => 'esperar_ate', 'condicao' => caro['condicao'], 'prazo' => { 'valor' => 1, 'unidade' => 'dias' },
        'se_vencer' => [prioridade_passo('a2', 'low')] }
    end

    it 'esperar até o valor passar de 1000: com a chave, segue na hora' do
      execucao = rodar(automacao_ligada(account, dono, [esperar_caro, prioridade_passo('a1', 'high')], gatilho: gatilho))

      expect([execucao.reload.estado, conversa.reload.priority]).to eq(%w[concluida high])
    end

    it 'esperar até o valor passar de 1000: sem a chave, o valor lê vazio e a espera não se cumpre' do
      definicao = automacao_ligada(account, dono, [esperar_caro, prioridade_passo('a1', 'high')], gatilho: gatilho)
      tirar_a_chave

      execucao = rodar(definicao)

      expect([execucao.reload.estado, conversa.reload.priority]).to eq(['esperando', nil])
    end

    # Sem account_user, o Valores já lê vazio (ver "quem não está na conta"); antes disso, a execução nem anda.
    it 'quem ligou saiu da conta: a execução não anda, nada escrito nem mandado' do
      definicao = automacao_ligada(account, dono, [caro, mensagem_passo('m1', 'Valor do pedido')], gatilho: gatilho)
      AccountUser.find_by(account: account, user: dono).destroy!

      execucao = rodar(definicao)

      expect(registros(execucao)).to eq([%w[inicio pulado quem_ligou_saiu_da_conta]])
      expect(conversa.reload.priority).to be_nil
      expect(conversa.messages.where('content LIKE ? OR content LIKE ?', '%2500%', 'Valor:%')).to be_empty
    end
  end

  # A leitura "card" do Decisores::Estado leva o valor só com a chave de quem ligou (#2597) e só no "decidir" (#2780: o
  # passo que escreve nunca o leva). Desde o #2679 (`le: card`), o card inteiro só vai se quem ligou ainda o vê: quem
  # saiu da conta não manda nem o título.
  describe 'leitura do card no passo de IA' do
    let(:dono) { pessoa_com(base + %w[sales_value_view]) }

    def resumir = { 'id' => 'r1', 'tipo' => 'resumir', 'le' => %w[card], 'linhas' => 2, 'destino' => 'nota' }

    def decidir
      { 'id' => 'd1', 'tipo' => 'decidir', 'le' => %w[card], 'pergunta' => 'É venda grande?', 'nenhum' => [],
        'caminhos' => [{ 'nome' => 'Grande', 'chave' => 'grande', 'descricao' => 'valor alto', 'passos' => [] }] }
    end

    def card_lido(definicao, passo = decidir)
      card
      execucao = Autonomia::Automacao::Execucao.find_or_create_by!(
        account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: card, chave_gatilho: 'card.ganho'
      )
      classe = passo['tipo'] == 'decidir' ? Autonomia::Automacao::PassoDeDecidir : Autonomia::Automacao::PassoDeResumir
      classe.new(execucao: execucao, passo: passo, alvo: card, acesso: nil).send(:leitura).conversa[:card]
    end

    it 'quem ligou tem a chave: o decidir leva o valor; o resumir, não' do
      definicao = automacao_ligada(account, dono, [caro], gatilho: gatilho)

      expect(card_lido(definicao)).to include(value: '2500.0 BRL')
      expect(card_lido(definicao, resumir)).to include(title: 'Pedido')
      expect(card_lido(definicao, resumir)).not_to have_key(:value)
    end

    it 'quem ligou perdeu a chave: o card vai sem o valor; saiu da conta: o card não vai', :aggregate_failures do
      definicao = automacao_ligada(account, dono, [caro], gatilho: gatilho)
      AccountUser.find_by(account: account, user: dono).custom_role.update!(permissions: base)
      lido = card_lido(definicao)
      expect([lido[:title], lido.key?(:value)]).to eq(['Pedido', false])

      AccountUser.find_by(account: account, user: dono).destroy!
      expect(card_lido(definicao)).to be_nil
    end
  end

  # O "Testar este passo" (#2500 C2) lê como quem pede: o valor do card só com a chave dela, e só no "decidir" (#2780).
  describe 'leitura do card no testar' do
    def card_lido_no_teste(quem)
      card
      passo = { 'id' => 'r1', 'tipo' => 'decidir', 'le' => %w[card], 'pergunta' => 'É venda grande?', 'nenhum' => [],
                'caminhos' => [{ 'nome' => 'Grande', 'chave' => 'grande', 'descricao' => 'valor alto', 'passos' => [] }] }
      pedido = Autonomia::Automacao::TestarPasso::Pedido.new(receita: receita([passo]), passo_id: 'r1')
      teste = Autonomia::Automacao::TestarPasso.new(pedido: pedido, conta: account, account_user: na_conta(quem))
      teste.send(:leitura, conversa).conversa[:card]
    end

    it 'quem pede tem a chave: o card vai com o valor' do
      expect(card_lido_no_teste(pessoa_com(base + %w[sales_value_view]))).to include(value: '2500.0 BRL')
    end

    it 'quem pede não tem a chave: o card vai sem o valor' do
      lido = card_lido_no_teste(pessoa_com(base))
      expect([lido[:title], lido.key?(:value)]).to eq(['Pedido', false])
    end
  end
end
