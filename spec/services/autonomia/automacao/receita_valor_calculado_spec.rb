require 'rails_helper'

# G16 do #2414: o salvar aceita o valor calculado no corpo da ação e confere o que ele lê. O formato da ação continua
# conferido com um exemplo no lugar de cada valor calculado.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }

  before do
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'revisao',
                                         attribute_display_type: :date)
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'nivel',
                                         attribute_display_type: :text)
  end

  def receita(corpo, acao: 'POST conversations/:id/custom_attributes')
    { 'gatilho' => { 'tipo' => 'conversa.resolvida' },
      'passos' => [{ 'id' => 'p1', 'tipo' => 'acao', 'acao' => acao, 'descricao' => 'Gravar',
                     'caminho' => { 'id' => { '$valor' => 'conversa.id' } }, 'corpo' => corpo }] }
  end

  def atributo(valor) = { 'merge' => true, 'custom_attributes' => { 'revisao' => valor } }

  def problemas(corpo, **) = described_class.new(receita(corpo, **), conta: account, account_user: nil).problemas

  def frase(chave, **) = I18n.t("autonomia.automacao.receita.#{chave}", passo: 'p1', **)

  def data(origem) = { '$data' => { 'de' => origem, 'mais' => { 'valor' => 6, 'unidade' => 'meses' } } }

  it 'aceita as três formas' do
    corpo = { 'merge' => true, 'custom_attributes' => { 'revisao' => data('hoje'), 'nivel' => { '$valor' => 'contato.nome' },
                                                        'nota' => { '$texto' => ['indicado por ', { '$valor' => 'contato.nome' }] } } }

    expect(problemas(corpo)).to eq([])
  end

  it 'aceita a data que parte de um atributo de data' do
    expect(problemas(atributo(data({ '$valor' => 'conversa.atributos.revisao' })))).to eq([])
  end

  it 'recusa a data que parte de um atributo que não é data' do
    expect(problemas(atributo(data({ '$valor' => 'conversa.atributos.nivel' }))))
      .to eq([frase(:data_sem_data, caminho: 'conversa.atributos.nivel')])
  end

  it 'confere cada caminho lido como confere os do caminho da ação', :aggregate_failures do
    expect(problemas(atributo({ '$valor' => 'contato.apelido' }))).to eq([frase(:valor_desconhecido, caminho: 'contato.apelido')])
    # #2716: o gatilho de conversa lê o card dela, mas o id do card não entra na ação.
    expect(problemas(atributo({ '$texto' => ['oi ', { '$valor' => 'card.titulo' }] }))).to eq([])
    expect(problemas(atributo({ '$texto' => ['card ', { '$valor' => 'card.id' }] })))
      .to eq([frase(:card_da_conversa_so_le, caminho: 'card.id')])
    expect(problemas(atributo(data({ '$valor' => 'conversa.atributos.sumiu' }))))
      .to eq([frase(:atributo_inexistente, caminho: 'conversa.atributos.sumiu')])
  end

  it 'valor lido num campo com lista passa no salvar; o literal fora da lista continua recusado', :aggregate_failures do
    lido = { 'priority' => { '$valor' => 'conversa.atributos.nivel' } }

    expect(problemas(lido, acao: 'POST conversations/:id/toggle_priority')).to eq([])
    expect(problemas({ 'priority' => 'altissima' }, acao: 'POST conversations/:id/toggle_priority')).not_to be_empty
  end

  it 'recusa texto montado ou data calculada em campo que nunca os aceitaria (opções, sim/não)', :aggregate_failures do
    texto = { '$texto' => ['alta'] }

    expect(problemas({ 'priority' => texto }, acao: 'POST conversations/:id/toggle_priority'))
      .to eq([frase(:forma_nao_cabe, campo: 'priority')])
    expect(problemas({ 'merge' => data('hoje'), 'custom_attributes' => {} })).to include(frase(:forma_nao_cabe, campo: 'merge'))
  end

  it 'a data parte de um atributo de data do contato também' do
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_key: 'nascimento',
                                         attribute_display_type: :date)

    expect(problemas(atributo(data({ '$valor' => 'contato.atributos.nascimento' })))).to eq([])
  end

  it 'o formato continua pegando a chave que a ação não conhece, mesmo com valor calculado' do
    expect(problemas({ 'merge' => true, 'inventada' => data('hoje') }).join).to include('inventada')
  end

  it 'recusa a chave com "$" que não é uma das formas, em vez de gravar o texto literal' do
    expect(problemas(atributo({ '$soma' => [1, 2] }))).to eq([frase(:forma_desconhecida, chave: '$soma')])
  end

  describe 'esquema' do
    def valido?(valor) = described_class.esquema_valido?(receita(atributo(valor)))

    it 'aceita só as formas fechadas', :aggregate_failures do
      expect(valido?(data('hoje'))).to be(true)
      expect(valido?({ '$data' => { 'de' => 'hoje' } })).to be(true)
      expect(valido?({ '$data' => { 'de' => 'amanha' } })).to be(false)
      expect(valido?({ '$data' => { 'de' => 'hoje', 'mais' => { 'valor' => 1, 'unidade' => 'horas' } } })).to be(false)
      expect(valido?({ '$data' => { 'de' => 'hoje', 'mais' => { 'valor' => 1.5, 'unidade' => 'dias' } } })).to be(false)
      expect(valido?({ '$valor' => 'contato.nome', 'extra' => 1 })).to be(false)
      expect(valido?({ '$texto' => [] })).to be(false)
    end
  end
end
