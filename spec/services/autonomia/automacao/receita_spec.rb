require 'rails_helper'

# A travessia única da receita (#2500, F7): o salvar, o ligar e a chave de funis andam por todos os ramos, inclusive os
# caminhos do "decidir" e o "nenhum se aplica". Um ramo de fora deixaria a ação de dentro sem conferência.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }
  let(:passo_proibido) { { 'id' => 'x1', 'tipo' => 'acao', 'acao' => 'DELETE accounts/:id', 'descricao' => 'Apagar' } }

  def decidir(caminho: [], nenhum: [])
    { 'id' => 'd1', 'tipo' => 'decidir',
      'caminhos' => [{ 'chave' => 'sinistro', 'descricao' => 'batida', 'passos' => caminho },
                     { 'chave' => 'cotacao', 'descricao' => 'preço', 'passos' => [] }],
      'nenhum' => nenhum }
  end

  def receita(*passos)
    { 'gatilho' => { 'tipo' => 'conversa.criada' }, 'passos' => passos }
  end

  it 'anda pelos ramos fixos, pelos caminhos do decidir e pelo nenhum, na ordem' do
    se = { 'id' => 's1', 'tipo' => 'se', 'entao' => [{ 'id' => 'e1' }], 'senao' => [{ 'id' => 'e2' }] }
    todos = described_class.new(receita(se, decidir(caminho: [{ 'id' => 'c1' }], nenhum: [{ 'id' => 'n1' }])), conta: account)

    expect(todos.passos.pluck('id')).to eq(%w[s1 e1 e2 d1 c1 n1])
  end

  it 'confere a ação de dentro de um caminho do decidir no salvar' do
    problemas = described_class.new(receita(decidir(caminho: [passo_proibido])), conta: account).problemas

    expect(problemas).to include(I18n.t('autonomia.automacao.receita.acao_fora', passo: 'x1', acao: 'DELETE accounts/:id'))
  end

  it 'confere a ação de dentro do nenhum se aplica no salvar' do
    problemas = described_class.new(receita(decidir(nenhum: [passo_proibido])), conta: account).problemas

    expect(problemas).to include(I18n.t('autonomia.automacao.receita.acao_fora', passo: 'x1', acao: 'DELETE accounts/:id'))
  end

  it 'recusa o id repetido entre um caminho e o nenhum' do
    repetido = decidir(caminho: [{ 'id' => 'p9', 'tipo' => 'parar' }], nenhum: [{ 'id' => 'p9', 'tipo' => 'parar' }])

    expect(described_class.new(receita(repetido), conta: account).problemas)
      .to include(I18n.t('autonomia.automacao.receita.id_repetido', passo: 'p9'))
  end

  it 'ignora só o caminho fora do formato, sem perder os outros' do
    torto = { 'id' => 'd1', 'tipo' => 'decidir', 'nenhum' => 'texto',
              'caminhos' => ['texto', { 'chave' => 'a' }, { 'chave' => 'b', 'passos' => [{ 'id' => 'x' }] }] }

    expect(described_class.ramos(torto)).to eq([[{ 'id' => 'x' }]])
  end

  # #2499: o gatilho de card pede a flag da F6 e o CRM; a etapa e o funil do gatilho são da conta, e "entrou" e "saiu"
  # pedem a etapa (esquema).
  describe 'gatilho de card' do
    around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
    let(:outra_conta) { create_crm_pipeline(account: create(:account), user: admin) }

    def de_card(gatilho) = { 'gatilho' => gatilho, 'passos' => [{ 'id' => 'p1', 'tipo' => 'parar' }] }

    def problemas(gatilho) = described_class.new(de_card(gatilho), conta: account).problemas

    before { account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos') }

    it 'aceita a etapa e o funil da conta', :aggregate_failures do
      expect(problemas('tipo' => 'card.entrou_na_etapa', 'etapa_id' => funil_e_etapa.last.id)).to be_empty
      expect(problemas('tipo' => 'card.ganho', 'funil_id' => funil_e_etapa.first.id)).to be_empty
      expect(problemas('tipo' => 'card.perdido')).to be_empty
    end

    it 'recusa a etapa e o funil de outra conta', :aggregate_failures do
      expect(problemas('tipo' => 'card.saiu_da_etapa', 'etapa_id' => outra_conta.last.id))
        .to eq([I18n.t('autonomia.automacao.receita.etapa_de_fora', id: outra_conta.last.id)])
      expect(problemas('tipo' => 'card.criado', 'funil_id' => outra_conta.first.id))
        .to eq([I18n.t('autonomia.automacao.receita.funil_de_fora', id: outra_conta.first.id)])
    end

    it 'recusa o gatilho de card sem a flag ou sem o CRM', :aggregate_failures do
      account.disable_features!('automacao_gatilhos')
      expect(problemas('tipo' => 'card.ganho')).to eq([I18n.t('autonomia.automacao.receita.gatilho_desligado')])

      account.enable_features!('automacao_gatilhos')
      with_modified_env(CRM_KANBAN_ENABLED: 'false') do
        expect(problemas('tipo' => 'card.ganho')).to eq([I18n.t('autonomia.automacao.receita.gatilho_desligado')])
      end
    end

    it 'o esquema pede a etapa em "entrou" e "saiu", e não aceita etapa nem funil fora do gatilho deles', :aggregate_failures do
      expect(described_class.esquema_valido?(de_card('tipo' => 'card.entrou_na_etapa'))).to be(false)
      expect(described_class.esquema_valido?(de_card('tipo' => 'card.ganho', 'etapa_id' => 1))).to be(false)
      expect(described_class.esquema_valido?(de_card('tipo' => 'card.saiu_da_etapa', 'etapa_id' => 1, 'funil_id' => 1))).to be(false)
      expect(described_class.esquema_valido?(de_card('tipo' => 'conversa.criada', 'funil_id' => 1))).to be(false)
      expect(described_class.esquema_valido?(de_card('tipo' => 'card.saiu_da_etapa', 'etapa_id' => 1))).to be(true)
    end

    it 'card.* vale no gatilho de card e não no de conversa', :aggregate_failures do
      filtro = [{ 'campo' => { '$valor' => 'card.valor' }, 'op' => 'maior', 'valor' => 0 }]
      expect(problemas('tipo' => 'card.ganho', 'filtros' => filtro)).to be_empty
      expect(problemas('tipo' => 'conversa.criada', 'filtros' => filtro)).to include(a_string_including('card.valor'))
    end
  end
end
