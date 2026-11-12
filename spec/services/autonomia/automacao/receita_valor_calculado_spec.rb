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

  def texto_em_nivel(partes) = { 'merge' => true, 'custom_attributes' => { 'nivel' => { '$texto' => partes } } }

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
    # O texto montado vai num atributo de texto (#2632): o `nivel`.
    expect(problemas(texto_em_nivel(['oi ', { '$valor' => 'card.titulo' }]))).to eq([])
    expect(problemas(texto_em_nivel(['card ', { '$valor' => 'card.id' }])))
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

  # #2632: a forma tem de caber no tipo do atributo da conta; a chave que a conta não tem segue aceita ('nota' acima).
  describe 'no atributo personalizado de outro tipo' do
    before do
      create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'pontos',
                                           attribute_display_type: :number)
      create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'site',
                                           attribute_display_type: :link)
    end

    def no(chave, valor) = { 'merge' => true, 'custom_attributes' => { chave => valor } }

    let(:montado) { { '$texto' => ['indicado por ', { '$valor' => 'contato.nome' }] } }

    it 'recusa a data calculada fora do atributo de data', :aggregate_failures do
      expect(problemas(no('pontos', data('hoje')))).to eq([frase(:data_fora_do_atributo, chave: 'pontos')])
      expect(problemas(no('nivel', data('hoje')))).to eq([frase(:data_fora_do_atributo, chave: 'nivel')])
    end

    it 'recusa o texto montado fora do atributo de texto', :aggregate_failures do
      expect(problemas(no('pontos', montado))).to eq([frase(:texto_fora_do_atributo, chave: 'pontos')])
      expect(problemas(no('revisao', montado))).to eq([frase(:texto_fora_do_atributo, chave: 'revisao')])
    end

    it 'aceita cada forma no tipo dela, e o $valor em qualquer um', :aggregate_failures do
      expect(problemas(no('revisao', data('hoje')))).to eq([])
      expect(problemas(no('nivel', montado))).to eq([])
      expect(problemas(no('site', montado))).to eq([])
      expect(problemas(no('pontos', { '$valor' => 'contato.nome' }))).to eq([])
    end

    it 'olha o atributo do modelo que a ação grava: o do card no card, não o da conversa de mesma chave' do
      create(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_key: 'nivel',
                                           attribute_display_type: :list, attribute_values: %w[a b])
      corpo = { 'card' => { 'custom_attributes' => { 'nivel' => montado } } }
      passo = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'PATCH crm/cards/:id', 'descricao' => 'Gravar',
                'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => corpo }
      receita = { 'gatilho' => { 'tipo' => 'card.ganho' }, 'passos' => [passo] }

      expect(described_class.new(receita, conta: account, account_user: nil).problemas).to include(frase(:texto_fora_do_atributo, chave: 'nivel'))
    end
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

    it 'o "fim do" aceita só o mês (#2705)', :aggregate_failures do
      expect(valido?(data('hoje').deep_merge('$data' => { 'fim_do' => 'mes' }))).to be(true)
      expect(valido?({ '$data' => { 'de' => 'hoje', 'fim_do' => 'mes' } })).to be(true)
      expect(valido?({ '$data' => { 'de' => 'hoje', 'fim_do' => 'semana' } })).to be(false)
      expect(valido?({ '$data' => { 'de' => 'hoje', 'fim_do' => true } })).to be(false)
    end
  end
end
