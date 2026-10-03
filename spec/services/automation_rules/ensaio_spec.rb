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
