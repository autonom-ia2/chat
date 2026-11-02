require 'rails_helper'

# A receita conferida ao salvar (#2414 F3, #2459).
RSpec.describe Autonomia::Automacao::Versao do
  let(:automacao) { create(:autonomia_automacao) }

  around { |exemplo| I18n.with_locale(:pt_BR) { exemplo.run } }

  def esperar(id = 'p1') = { 'id' => id, 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }

  def por_etiqueta(id = 'p2', caminho: { 'conversation_id' => { '$valor' => 'conversa.id' } }, corpo: { 'por' => ['pos-venda'] })
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'PATCH conversations/:conversation_id/labels/alterar', 'caminho' => caminho,
      'corpo' => corpo, 'descricao' => 'Pôr a etiqueta pós-venda' }
  end

  def receita(*passos, gatilho: { 'tipo' => 'conversa.resolvida' }) = { 'gatilho' => gatilho, 'passos' => passos }

  def versao(receita, autor: nil)
    build(:autonomia_automacao_versao, automacao: automacao, account: automacao.account, receita: receita, autor: autor)
  end

  def erros(receita) = versao(receita).tap(&:validate).errors.full_messages.join("\n")

  it 'aceita "quando resolver, espere 1 dia e ponha a etiqueta pós-venda" (F3.1)' do
    expect(versao(receita(esperar, por_etiqueta))).to be_valid
  end

  it 'recusa ação fora da lista de permitidas (F3.2)' do
    apagar_usuario = { 'id' => 'p2', 'tipo' => 'acao', 'acao' => 'DELETE agents/:id', 'caminho' => { 'id' => 7 },
                       'descricao' => 'Apagar o agente' }

    expect(erros(receita(esperar, apagar_usuario))).to include('DELETE agents/:id não pode ser passo de automação')
  end

  it 'recusa apagar etiqueta (F3.11)' do
    apagar = { 'id' => 'p2', 'tipo' => 'acao', 'acao' => 'DELETE labels/:id', 'caminho' => { 'id' => 3 }, 'descricao' => 'Apagar' }

    expect(erros(receita(apagar))).to include('DELETE labels/:id não pode ser passo de automação')
  end

  describe 'etiqueta criada pela automação (F3.10)' do
    def criar_etiqueta(corpo) = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST labels', 'corpo' => corpo, 'descricao' => 'Criar' }

    it 'recusa sem descrição' do
      expect(erros(receita(criar_etiqueta({ 'title' => 'renovacao' })))).to include('falta description')
    end

    it 'aceita com descrição' do
      expect(versao(receita(criar_etiqueta({ 'title' => 'renovacao', 'description' => 'Cliente em renovação' })))).to be_valid
    end
  end

  it 'manda o atributo da conversa sempre com merge, para não apagar os outros' do
    atributo = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Origem',
                 'caminho' => { 'id' => { '$valor' => 'conversa.id' } }, 'corpo' => { 'custom_attributes' => { 'origem' => 'site' } } }

    expect(erros(receita(atributo))).to include('Passo p1: merge tem de ser true')
    expect(versao(receita(atributo.deep_merge('corpo' => { 'merge' => true })))).to be_valid
  end

  it 'não troca a chave nem o modelo de um atributo' do
    alterar = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'PATCH custom_attribute_definitions/:id', 'caminho' => { 'id' => 4 },
                'descricao' => 'Renomear', 'corpo' => { 'custom_attribute_definition' => { 'attribute_key' => 'outra' } } }

    expect(erros(receita(alterar))).to include('Passo p1: a automação não muda custom_attribute_definition.attribute_key')
  end

  it 'recusa ação fora da lista dentro do senão e do se_vencer' do
    apagar = ->(id) { { 'id' => id, 'tipo' => 'acao', 'acao' => 'DELETE agents/:id', 'caminho' => { 'id' => 7 }, 'descricao' => 'Apagar' } }
    condicao = { 'campo' => { '$valor' => 'conversa.status' }, 'op' => 'igual', 'valor' => 'open' }
    se = { 'id' => 's1', 'tipo' => 'se', 'condicao' => condicao, 'entao' => [esperar('p2')], 'senao' => [apagar.call('p3')] }
    ate = { 'id' => 'e1', 'tipo' => 'esperar_ate', 'condicao' => condicao, 'prazo' => { 'valor' => 1, 'unidade' => 'dias' },
            'se_vencer' => [apagar.call('p4')] }

    expect(erros(receita(se, ate))).to include('Passo p3: DELETE agents/:id', 'Passo p4: DELETE agents/:id')
  end

  describe 'contato e empresa' do
    def alterar(acao, corpo)
      { 'id' => 'p1', 'tipo' => 'acao', 'acao' => acao, 'caminho' => { 'id' => 9 }, 'descricao' => 'Alterar', 'corpo' => corpo }
    end

    it 'não troca a foto (buscaria uma URL de fora) nem bloqueia o contato', :aggregate_failures do
      expect(erros(receita(alterar('PATCH contacts/:id', { 'avatar_url' => 'https://exemplo.test/a.png' })))).to include('muda avatar_url')
      expect(erros(receita(alterar('PUT contacts/:id', { 'blocked' => true })))).to include('muda blocked')
      expect(erros(receita(alterar('PATCH companies/:id', { 'company' => { 'avatar' => 'x' } })))).to include('muda avatar')
      expect(erros(receita(alterar('PUT companies/:id', { 'avatar' => 'x' })))).to include('muda avatar')
      expect(versao(receita(alterar('PATCH contacts/:id', { 'name' => 'Ana Souza' })))).to be_valid
    end
  end

  describe 'atributo personalizado' do
    let(:condicao) { { 'campo' => { '$valor' => 'contato.atributos.placa' }, 'op' => 'preenchido' } }

    it 'recusa a chave que a conta não tem, e aceita depois de criar o atributo', :aggregate_failures do
      se = { 'id' => 's1', 'tipo' => 'se', 'condicao' => condicao, 'entao' => [esperar('p2')] }

      expect(erros(receita(se))).to include('Passo s1: a conta não tem o atributo de contato.atributos.placa')

      create(:custom_attribute_definition, account: automacao.account, attribute_model: 'conversation_attribute', attribute_key: 'placa')
      expect(versao(receita(se))).not_to be_valid

      create(:custom_attribute_definition, account: automacao.account, attribute_model: 'contact_attribute', attribute_key: 'placa')
      expect(versao(receita(se))).to be_valid
    end
  end

  it 'recusa variável no corpo da ação (chega com a mensagem, F4)' do
    expect(erros(receita(por_etiqueta(corpo: { 'por' => [{ '$valor' => 'contato.nome' }] }))))
      .to include('o corpo da ação ainda não aceita variável')
  end

  it 'pede o valor da comparação e põe teto na espera' do
    sem_valor = { 'id' => 'p1', 'tipo' => 'se', 'condicao' => { 'campo' => { '$valor' => 'conversa.status' }, 'op' => 'igual' },
                  'entao' => [esperar('p2')] }
    longa = { 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 3651, 'unidade' => 'dias' } }

    expect(versao(receita(sem_valor))).not_to be_valid
    expect(versao(receita(longa))).not_to be_valid
  end

  it 'recusa corpo fora do formato da ação, como o Guia' do
    expect(erros(receita(por_etiqueta(corpo: { 'labels' => ['x'] })))).to include('campo que esta ação não tem: labels')
  end

  it 'recusa ação sem parâmetro do caminho' do
    expect(erros(receita(por_etiqueta(caminho: {})))).to include('a ação precisa de conversation_id')
  end

  it 'recusa valor que a automação não sabe ler' do
    caminho = { 'conversation_id' => { '$valor' => 'conversa.senha' } }

    expect(erros(receita(por_etiqueta(caminho: caminho)))).to include('a automação não sabe ler conversa.senha')
  end

  it 'recusa condição com valor desconhecido, também no filtro do gatilho' do
    condicao = { 'campo' => { '$valor' => 'card.valor' }, 'op' => 'maior', 'valor' => 10 }
    se = { 'id' => 'p2', 'tipo' => 'se', 'condicao' => condicao, 'entao' => [por_etiqueta('p3')] }

    expect(erros(receita(se))).to include('Passo p2: a automação não sabe ler card.valor')
    expect(erros(receita(esperar, gatilho: { 'tipo' => 'conversa.resolvida', 'filtros' => [condicao] })))
      .to include('Passo gatilho: a automação não sabe ler card.valor')
  end

  it 'recusa id repetido, mesmo dentro de um ramo' do
    se = { 'id' => 'p2', 'tipo' => 'se', 'condicao' => { 'campo' => { '$valor' => 'conversa.etiquetas' }, 'op' => 'vazio' },
           'entao' => [esperar('p1')] }

    expect(erros(receita(esperar('p1'), se))).to include('Passo p1: o id já é de outro passo')
  end

  it 'recusa o que o esquema não conhece' do
    expect(versao(receita({ 'id' => 'p1', 'tipo' => 'mandar_pix' }))).not_to be_valid
    expect(versao(receita(esperar, gatilho: { 'tipo' => 'card.ganho' }))).not_to be_valid
    expect(versao(receita)).not_to be_valid
  end

  it 'recusa autor de fora da conta' do
    expect(versao(receita(esperar), autor: create(:user))).not_to be_valid
    expect(versao(receita(esperar), autor: create(:user, account: automacao.account))).to be_valid
  end
end
