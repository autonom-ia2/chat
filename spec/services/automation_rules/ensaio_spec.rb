require 'rails_helper'

# Ensaio da automação (#859): diz o que a regra faria nas conversas recentes, e não faz.
RSpec.describe AutomationRules::Ensaio do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:outra_caixa) { create(:inbox, account: account) }
  let(:condicao_sinistro) do
    { 'attribute_key' => 'content', 'filter_operator' => 'contains', 'values' => ['sinistro'], 'query_operator' => nil }
  end
  let(:rule) do
    create(:automation_rule, account: account, active: false, event_name: 'message_created',
                             conditions: [condicao_sinistro],
                             actions: [{ 'action_name' => 'add_label', 'action_params' => ['sinistro'] },
                                       { 'action_name' => 'send_message', 'action_params' => ['Recebemos seu aviso.'] }])
  end

  def conversa_com(texto, caixa: inbox, nome: 'Maria')
    contato = create(:contact, account: account, name: nome)
    conversa = create(:conversation, account: account, inbox: caixa, contact: contato)
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, content: texto)
    conversa
  end

  def resultado_de(conversa, resultado)
    resultado['resultados'].find { |item| item['conversation_id'] == conversa.id }
  end

  it 'diz quais conversas casam e o que faria em cada uma', :aggregate_failures do
    casa = conversa_com('Tive um sinistro com o carro', nome: 'Maria')
    nao_casa = conversa_com('Quero uma cotação', nome: 'João')

    resultado = described_class.new(rule: rule, user: admin).perform

    expect(resultado_de(casa, resultado)).to include('casou' => true, 'contato' => 'Maria',
                                                     'display_id' => casa.display_id,
                                                     'faria' => %w[add_label send_message])
    expect(resultado_de(nao_casa, resultado)).to include('casou' => false, 'faria' => [])
    expect(resultado['sem_teste']).to eq([])
    expect(resultado['depende_do_decisor']).to eq([])
  end

  # Revisão de integração (#858 x #859): o ensaio não pergunta ao Decisor, então não pode prometer
  # os passos que só rodam depois da resposta dele.
  it 'para a lista no passo do Decisor e devolve os passos seguintes como dependentes', :aggregate_failures do
    decisor = create(:autonomia_decisor, account: account)
    rule.update!(actions: [{ 'action_name' => 'add_label', 'action_params' => ['sinistro'] },
                           { 'action_name' => 'perguntar_ao_decisor', 'action_params' => [decisor.id, 'sim'] },
                           { 'action_name' => 'send_message', 'action_params' => ['Recebemos seu aviso.'] }])
    casa = conversa_com('Tive um sinistro')

    resultado = described_class.new(rule: rule, user: admin).perform

    expect(resultado_de(casa, resultado)['faria']).to eq(%w[add_label perguntar_ao_decisor])
    expect(resultado['depende_do_decisor']).to eq(%w[send_message])
  end

  it 'não executa nenhuma ação nem grava nada', :aggregate_failures do
    conversa = conversa_com('sinistro na garagem')
    expect(AutomationRules::ActionService).not_to receive(:new)

    expect { described_class.new(rule: rule, user: admin).perform }
      .not_to(change { [Message.count, conversa.reload.label_list, rule.reload.attributes] })
  end

  it 'deixa de fora a condição "mudou de valor" e avisa', :aggregate_failures do
    mudou = { 'attribute_key' => 'status', 'filter_operator' => 'attribute_changed',
              'values' => { 'from' => ['open'], 'to' => ['resolved'] }, 'query_operator' => nil }
    rule.update!(conditions: [condicao_sinistro.merge('query_operator' => 'AND'), mudou])
    conversa = conversa_com('meu sinistro')

    resultado = described_class.new(rule: rule, user: admin).perform

    expect(resultado['sem_teste']).to eq(['status'])
    expect(resultado_de(conversa, resultado)['casou']).to be(true)
  end

  # Revisão #859: sem nenhuma condição testável, o filtro rodava sem filtro nenhum e
  # dizia que a regra pegaria TODAS as conversas.
  it 'regra só com "mudou de valor" não finge que pegaria todas as conversas', :aggregate_failures do
    mudou = { 'attribute_key' => 'status', 'filter_operator' => 'attribute_changed',
              'values' => { 'from' => ['open'], 'to' => ['resolved'] }, 'query_operator' => nil }
    rule.update!(event_name: 'conversation_updated', conditions: [mudou])
    conversa_com('obrigado')

    resultado = described_class.new(rule: rule, user: admin).perform

    expect(resultado['testavel']).to be(false)
    expect(resultado['resultados']).to eq([])
    expect(resultado['sem_teste']).to eq(['status'])
  end

  # Revisão #859: o listener dispara para qualquer mensagem que não seja de atividade —
  # inclusive as enviadas e as notas privadas —, e o ensaio olhava só as recebidas.
  it 'mensagem enviada conta, como no listener; atividade não', :aggregate_failures do
    rule.update!(conditions: [{ 'attribute_key' => 'message_type', 'filter_operator' => 'equal_to',
                                'values' => ['outgoing'], 'query_operator' => nil }])
    respondida = conversa_com('oi')
    create(:message, account: account, inbox: inbox, conversation: respondida, message_type: :outgoing, content: 'Olá!')
    so_atividade = conversa_com('oi')
    create(:message, account: account, inbox: inbox, conversation: so_atividade, message_type: :activity, content: 'Resolvida')

    resultado = described_class.new(rule: rule, user: admin).perform

    expect(resultado['testavel']).to be(true)
    expect(resultado_de(respondida, resultado)['casou']).to be(true)
    expect(resultado_de(so_atividade, resultado)['casou']).to be(false)
  end

  it 'só olha as conversas que a pessoa enxerga e respeita a quantidade', :aggregate_failures do
    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: inbox)
    visivel = conversa_com('sinistro')
    conversa_com('sinistro', caixa: outra_caixa)

    resultado = described_class.new(rule: rule, user: agente, quantidade: 50).perform

    expect(resultado['resultados'].pluck('conversation_id')).to eq([visivel.id])
  end

  # #1009: a regra presa a uma caixa testava as conversas recentes da conta inteira — 9 de 10 eram de
  # outra caixa, e o ensaio dizia "0 de 10" sem ter olhado a caixa da regra.
  describe 'regra presa a uma caixa' do
    let(:condicao_da_caixa) do
      { 'attribute_key' => 'inbox_id', 'filter_operator' => 'equal_to', 'values' => [inbox.id], 'query_operator' => 'AND' }
    end

    it 'testa só as conversas recentes daquela caixa', :aggregate_failures do
      rule.update!(conditions: [condicao_da_caixa, condicao_sinistro])
      da_caixa = conversa_com('sinistro')
      3.times { conversa_com('sinistro', caixa: outra_caixa) }

      resultado = described_class.new(rule: rule, user: admin, quantidade: 1).perform

      expect(resultado['resultados'].pluck('conversation_id')).to eq([da_caixa.id])
      expect(resultado_de(da_caixa, resultado)['casou']).to be(true)
    end

    it 'com OU entre as condições, a caixa não restringe a busca' do
      rule.update!(conditions: [condicao_da_caixa.merge('query_operator' => 'OR'), condicao_sinistro])
      conversa_com('oi')
      de_fora = conversa_com('sinistro', caixa: outra_caixa)

      resultado = described_class.new(rule: rule, user: admin).perform

      expect(resultado_de(de_fora, resultado)['casou']).to be(true)
    end
  end

  it 'recusa a regra com condição inválida sem marcar a regra de verdade', :aggregate_failures do
    # A validação recusaria a condição; é justamente a regra quebrada que se quer ensaiar.
    quebrada = [{ 'attribute_key' => 'campo_que_nao_existe', 'filter_operator' => 'equal_to', 'values' => ['x'],
                  'query_operator' => nil }]
    rule.update_column(:conditions, quebrada) # rubocop:disable Rails/SkipsModelValidations
    conversa_com('sinistro')

    expect { described_class.new(rule: rule, user: admin).perform }.to raise_error(described_class::Invalida)
    expect(rule.reload.authorization_error_count).to eq(0)
  end
end
