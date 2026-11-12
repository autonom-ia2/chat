require 'rails_helper'

# #2932–#2934: o salvar dos três passos novos com motor. Só com a flag automacao_passos_novos; cada um confere o que é da
# conta e o que quem salva pode, e o valor buscado (`consulta.<passo>.<chave>`) segue a régua do texto da IA.
RSpec.describe Autonomia::Automacao::Receita, :automacao_motor do
  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:quem_salva) { account.account_users.find_by(user: admin) }
  let(:frase) { 'autonomia.automacao.receita' }
  let(:etapa) { create_crm_pipeline(account: account, user: admin).last }
  let(:gatilho) { { 'tipo' => 'conversa.resolvida' } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_passos_novos', 'automacao_gatilhos')
  end

  def problemas(*passos, account_user: quem_salva)
    described_class.new({ 'gatilho' => gatilho, 'passos' => passos }, conta: account, account_user: account_user).problemas
  end

  def parar(id = 'fim') = { 'id' => id, 'tipo' => 'parar' }

  def para_cada(lista, cada = [parar('c1')], id: 'lista')
    { 'id' => id, 'tipo' => 'repetir_lista', 'lista' => lista, 'teto' => 50, 'ritmo' => 'aos_poucos', 'cada' => cada }
  end

  def consulta(id = 'busca', url: 'https://loja.exemplo.com/pedido', guardar: [{ 'nome' => 'Status do pedido', 'caminho' => 'pedido.status' }])
    { 'id' => id, 'tipo' => 'consultar', 'fonte' => { 'de' => 'endereco', 'url' => url }, 'guardar' => guardar }
  end

  def se_valor(id, caminho)
    { 'id' => id, 'tipo' => 'se', 'condicao' => { 'campo' => { '$valor' => caminho }, 'op' => 'existe' }, 'entao' => [parar("#{id}_sim")] }
  end

  def com_funcao(*permissoes)
    pessoa = create(:user, account: account, role: :agent)
    vinculo = pessoa.account_users.find_by(account: account)
    vinculo.update!(custom_role: create(:custom_role, account: account, permissions: permissoes))
    vinculo
  end

  it 'com a flag desligada, recusa os três com a frase', :aggregate_failures do
    account.disable_features!('automacao_passos_novos')

    expect(problemas(consulta)).to eq([I18n.t("#{frase}.passos_novos_desligados", passo: 'busca')])
    expect(problemas(para_cada({ 'de' => 'etiqueta', 'etiqueta' => 'vip' }))).to include(I18n.t("#{frase}.passos_novos_desligados", passo: 'lista'))
  end

  describe 'para cada um de uma lista (#2932)' do
    it 'aceita a etapa e a etiqueta da conta', :aggregate_failures do
      account.labels.create!(title: 'vip')

      expect(problemas(para_cada({ 'de' => 'etapa', 'etapa_id' => etapa.id }))).to be_empty
      expect(problemas(para_cada({ 'de' => 'etiqueta', 'etiqueta' => 'vip' }))).to be_empty
    end

    it 'recusa o que não é da conta', :aggregate_failures do
      outra_etapa = create_crm_pipeline(account: create(:account), user: admin).last

      expect(problemas(para_cada({ 'de' => 'etapa', 'etapa_id' => outra_etapa.id })))
        .to eq([I18n.t("#{frase}.lista.etapa_de_fora", passo: 'lista')])
      expect(problemas(para_cada({ 'de' => 'etiqueta', 'etiqueta' => 'nao-existe' })))
        .to eq([I18n.t("#{frase}.lista.etiqueta_de_fora", passo: 'lista')])
      expect(problemas(para_cada({ 'de' => 'publico', 'publico_id' => 999_999 })))
        .to eq([I18n.t("#{frase}.lista.publico_de_fora", passo: 'lista')])
    end

    it 'os cards da etapa pedem a chave de funis de quem salva' do
      expect(problemas(para_cada({ 'de' => 'etapa', 'etapa_id' => etapa.id }), account_user: com_funcao('automation_manage')))
        .to include(I18n.t("#{frase}.lista.sem_chave_de_funis", passo: 'lista'))
    end

    it 'o galho é conferido no item: na lista de contatos, card.* não existe' do
      account.labels.create!(title: 'vip')
      cada = [{ 'id' => 'c1', 'tipo' => 'se', 'condicao' => { 'campo' => { '$valor' => 'card.titulo' }, 'op' => 'existe' },
                'entao' => [parar('c2')] }]

      expect(problemas(para_cada({ 'de' => 'etiqueta', 'etiqueta' => 'vip' }, cada)))
        .to include(I18n.t("#{frase}.valor_fora_do_alvo", passo: 'c1', caminho: 'card.titulo'))
    end

    it 'não cabe dentro de outro "para cada"' do
      account.labels.create!(title: 'vip')
      dentro = para_cada({ 'de' => 'etiqueta', 'etiqueta' => 'vip' }, id: 'dentro')

      expect(problemas(para_cada({ 'de' => 'etiqueta', 'etiqueta' => 'vip' }, [dentro])))
        .to include(I18n.t("#{frase}.lista.aninhado", passo: 'dentro'))
    end
  end

  describe 'usar outra automação (#2933)' do
    def bloco(passos = [parar('b1')], gatilho_do_bloco: gatilho)
      create(:autonomia_automacao, account: account, bloco: true).tap do |definicao|
        definicao.salvar_versao!(receita: { 'gatilho' => gatilho_do_bloco, 'passos' => passos }, autor: admin)
      end
    end

    def usar(definicao, id = 'usar') = { 'id' => id, 'tipo' => 'usar_bloco', 'bloco_id' => definicao.id }

    it 'aceita o bloco da conta no mesmo tipo de registro' do
      expect(problemas(usar(bloco))).to be_empty
    end

    it 'recusa a automação que não é bloco, a de outra conta e o bloco de outro tipo de registro', :aggregate_failures do
      comum = create(:autonomia_automacao, account: account)
      de_fora = create(:autonomia_automacao, account: create(:account), bloco: true)
      de_card = bloco(gatilho_do_bloco: { 'tipo' => 'card.ganho' })

      expect(problemas(usar(comum))).to eq([I18n.t("#{frase}.bloco.de_fora", passo: 'usar')])
      expect(problemas(usar(de_fora))).to eq([I18n.t("#{frase}.bloco.de_fora", passo: 'usar')])
      expect(problemas(usar(de_card))).to eq([I18n.t("#{frase}.bloco.outro_alvo", passo: 'usar', bloco: de_card.nome)])
    end

    it 'recusa o laço (A usa B, que usa A) e bloco dentro de bloco além do limite', :aggregate_failures do
      a = bloco
      b = bloco([usar(a, 'b_usa_a')])
      expect { a.salvar_versao!(receita: { 'gatilho' => gatilho, 'passos' => [usar(b, 'a_usa_b')] }, autor: admin) }
        .to(raise_error(ActiveRecord::RecordInvalid) do |erro|
          expect(erro.record.errors[:receita]).to include(I18n.t("#{frase}.bloco.laco_volta", bloco: b.nome))
        end)

      fundo = bloco
      3.times { fundo = bloco([usar(fundo, "n#{fundo.id}")]) }
      expect(problemas(usar(fundo)))
        .to eq([I18n.t("#{frase}.bloco.fundo", passo: 'usar', bloco: fundo.nome, maximo: Autonomia::Automacao::Bloco::PROFUNDIDADE)])
    end

    it 'o bloco não liga sozinho' do
      definicao = bloco

      expect(definicao.assumir_e_religar!(admin, versao_id: definicao.versao_ativa_id).motivo).to eq('bloco_nao_liga')
    end
  end

  describe 'buscar informação em outro sistema (#2934)' do
    it 'aceita o endereço https e os dados com nome' do
      expect(problemas(consulta)).to be_empty
    end

    it 'pede a chave de integrações de quem salva' do
      expect(problemas(consulta, account_user: com_funcao('automation_manage')))
        .to eq([I18n.t("#{frase}.consulta.sem_permissao", passo: 'busca')])
    end

    it 'recusa endereço sem https, interno, integração que não existe, nome sem letra, nome repetido e caminho vazio', :aggregate_failures do
      expect(problemas(consulta(url: 'http://loja.exemplo.com/x'))).to eq([I18n.t("#{frase}.consulta.consulta_so_https", passo: 'busca')])
      expect(problemas(consulta(url: 'https://127.0.0.1/x'))).to eq([I18n.t("#{frase}.consulta.consulta_endereco_interno", passo: 'busca')])
      integracao = consulta.merge('fonte' => { 'de' => 'integracao', 'id' => 'loja' })
      expect(problemas(integracao)).to eq([I18n.t("#{frase}.consulta.integracao_desconhecida", passo: 'busca')])
      repetidos = [{ 'nome' => 'Status', 'caminho' => 'a' }, { 'nome' => 'status!', 'caminho' => 'b' }]
      expect(problemas(consulta(guardar: repetidos))).to eq([I18n.t("#{frase}.consulta.nome_repetido", passo: 'busca', chave: 'status')])
      expect(problemas(consulta(guardar: [{ 'nome' => '!!', 'caminho' => 'a..b' }])))
        .to eq([I18n.t("#{frase}.consulta.nome_sem_letra", passo: 'busca', nome: '!!'),
                I18n.t("#{frase}.consulta.caminho_invalido", passo: 'busca', caminho: 'a..b')])
    end

    it 'o dado buscado vale depois do passo que busca, com a chave do nome', :aggregate_failures do
      expect(problemas(consulta, se_valor('depois', 'consulta.busca.status_do_pedido'))).to be_empty
      expect(problemas(se_valor('antes', 'consulta.busca.status_do_pedido'), consulta))
        .to eq([I18n.t("#{frase}.consulta_depois", passo: 'antes', caminho: 'consulta.busca.status_do_pedido')])
      expect(problemas(consulta, se_valor('outra', 'consulta.busca.outra_coisa')))
        .to eq([I18n.t("#{frase}.consulta_sem_passo", passo: 'outra', caminho: 'consulta.busca.outra_coisa')])
    end

    it 'a chave do nome: minúsculas, sem acento, o resto vira "_"' do
      expect(Autonomia::Automacao::PassoConsultar.chave('  Previsão de Entrega (dia) ')).to eq('previsao_de_entrega_dia')
    end
  end
end
