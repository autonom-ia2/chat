# A sonda da G70 (#2880, decisão 20 do Rodrigo, 10/11, "IA só anota campos"; exemplos 2 e 7: "grava no card"), por
# comportamento: numa automação de conversa, o salvar aceita o "extrair" com destino num campo do card e recusa o valor
# protegido (`card.valor`, decisão 9) com a frase `destino_invalido`; ao rodar (`executar`, com a resposta da IA num
# receptor WebMock), o extrair grava no card da conversa pela porta da frente (o PATCH do card, como quem ligou), e o
# campo passa a ter o valor que a IA devolveu. Fica fora do FechamentoAutomacao::Lacunas, que já está no limite de
# tamanho; o SONDAS de lá chama a daqui. Roda na transação do exemplo, que desfaz tudo.
module FechamentoAutomacao::SondasDoExtrairNoCard
  extend CrmHelpers
  extend WebMock::API

  module_function

  GATILHO = { 'tipo' => 'mensagem.criada' }.freeze
  # O que a IA devolve: só existe aqui e na resposta do receptor, nunca na conversa.
  ACHADO = 'sonda-g70-blazer'.freeze

  def extrair_grava_no_card_da_conversa?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') do
      account, dona, conversa = cenario
      card = card_da_conversa(account, dona, conversa)
      definicao = FechamentoAutomacao::Comportamento.ligada(account, dona, GATILHO, [passo('card.atributos.peca')])
      definicao.present? && valor_recusado?(account, dona) && executou?(definicao, conversa) &&
        card.reload.custom_attributes['peca'] == ACHADO
    end
  end

  def cenario
    account = FactoryBot.create(:account)
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_ia')
    dona = FactoryBot.create(:user, account: account, role: :administrator)
    FactoryBot.create(:custom_attribute_definition, account: account, attribute_key: 'peca', attribute_display_name: 'Peça',
                                                    attribute_model: 'card_attribute', attribute_display_type: 'text')
    ia_da_conta(account)
    conversa = FactoryBot.create(:conversation, account: account)
    FactoryBot.create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Quero ver uma peça')
    [account, dona, conversa]
  end

  # A chave da conta e a IA num receptor WebMock (a conferência da chave e a resposta do extrair).
  def ia_da_conta(account)
    stub_request(:get, 'https://api.openai.com/v1/models').to_return(status: 200, body: '{}')
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { id: 'g70', output_text: { 'peca' => ACHADO }.to_json, usage: { input_tokens: 1, output_tokens: 1 } }.to_json
    )
    FactoryBot.create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'sonda-g70' })
  end

  def passo(destino)
    { 'id' => 'g70', 'tipo' => 'extrair', 'le' => %w[mensagens_recentes],
      'campos' => [{ 'chave' => 'peca', 'descricao' => 'a peça pedida', 'destino' => destino }] }
  end

  # O salvar recusa o valor protegido como destino, com a frase de destino inválido.
  def valor_recusado?(account, dona)
    receita = { 'gatilho' => GATILHO, 'passos' => [passo('card.valor')] }
    frase = I18n.t('autonomia.automacao.receita.destino_invalido', passo: 'g70', destino: 'card.valor')
    Autonomia::Automacao::Receita.new(receita, conta: account, account_user: AccountUser.find_by(account: account, user: dona))
                                 .problemas.include?(frase)
  end

  def card_da_conversa(account, dona, conversa)
    funil, etapa = create_crm_pipeline(account: account, user: dona)
    Crm::Cards::Creator.new(account: account, user: dona, params: { pipeline_id: funil.id, stage_id: etapa.id, title: 'Sonda G70',
                                                                    contact_id: conversa.contact_id, conversation_id: conversa.id }).perform
  end

  # O passo inteiro (`executar`): a pergunta à IA, a resposta e a escrita.
  def executou?(definicao, conversa)
    execucao = FactoryBot.create(:autonomia_automacao_execucao, automacao: definicao, versao: definicao.versao_ativa, alvo: conversa,
                                                                chave_gatilho: GATILHO['tipo'])
    passo = definicao.versao_ativa.receita['passos'].first
    acesso = Autonomia::Automacao::Acesso.new(definicao, chave_gatilho: execucao.chave_gatilho)
    resultado = Autonomia::Automacao::PassoDeExtrair.new(execucao: execucao, passo: passo, alvo: conversa, acesso: acesso).executar
    resultado.tipo == :ok && resultado.dados.dig('campos', 'gravados') == ['peca']
  end
end
