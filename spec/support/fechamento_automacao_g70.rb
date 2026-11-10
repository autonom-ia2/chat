# A sonda da G70 (#2880, decisão 20 do Rodrigo, 10/11, "IA só anota campos"; exemplos 2 e 7: "grava no card"), por
# comportamento: numa automação de conversa, o salvar aceita o "extrair" com destino num campo do card e recusa o valor
# protegido (`card.valor`, decisão 9); ao rodar, o extrair grava no card da conversa pela porta da frente (o PATCH do
# card, como quem ligou), e o campo passa a ter o valor. A pergunta à IA fica de fora: a sonda entrega o achado e
# confere a escrita. Fica fora do FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a
# daqui. Roda na transação do exemplo, que desfaz tudo.
module FechamentoAutomacao::SondasDoExtrairNoCard
  extend CrmHelpers

  module_function

  GATILHO = { 'tipo' => 'mensagem.criada' }.freeze

  def extrair_grava_no_card_da_conversa?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      account = FactoryBot.create(:account)
      account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_ia')
      dona = FactoryBot.create(:user, account: account, role: :administrator)
      FactoryBot.create(:custom_attribute_definition, account: account, attribute_key: 'peca', attribute_display_name: 'Peça',
                                                      attribute_model: 'card_attribute', attribute_display_type: 'text')
      conversa = FactoryBot.create(:conversation, account: account)
      card = card_da_conversa(account, dona, conversa)
      definicao = FechamentoAutomacao::Comportamento.ligada(account, dona, GATILHO, [passo('card.atributos.peca')])
      return false if definicao.nil? || FechamentoAutomacao::Comportamento.ligada(account, dona, GATILHO, [passo('card.valor')])

      gravou?(definicao, conversa) && card.reload.custom_attributes['peca'] == 'vestido'
    end
  end

  def passo(destino)
    { 'id' => 'g70', 'tipo' => 'extrair', 'le' => %w[mensagens_recentes],
      'campos' => [{ 'chave' => 'peca', 'descricao' => 'a peça pedida', 'destino' => destino }] }
  end

  def card_da_conversa(account, dona, conversa)
    funil, etapa = create_crm_pipeline(account: account, user: dona)
    Crm::Cards::Creator.new(account: account, user: dona, params: { pipeline_id: funil.id, stage_id: etapa.id, title: 'Sonda G70',
                                                                    contact_id: conversa.contact_id, conversation_id: conversa.id }).perform
  end

  # O achado da IA ("vestido") vai à escrita do passo, a mesma que roda depois da resposta dela.
  def gravou?(definicao, conversa)
    execucao = FactoryBot.create(:autonomia_automacao_execucao, automacao: definicao, versao: definicao.versao_ativa, alvo: conversa,
                                                                chave_gatilho: GATILHO['tipo'])
    passo = definicao.versao_ativa.receita['passos'].first
    acesso = Autonomia::Automacao::Acesso.new(definicao, chave_gatilho: execucao.chave_gatilho)
    extrair = Autonomia::Automacao::PassoDeExtrair.new(execucao: execucao, passo: passo, alvo: conversa, acesso: acesso)
    gravados, falha, = extrair.send(:escrever, { passo['campos'].first => 'vestido' })
    falha.nil? && gravados == ['peca']
  end
end
