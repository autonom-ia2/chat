# As sondas do registro ligado (G18 e G65, exemplo 11): rodam o motor de verdade e conferem o efeito. Ficam fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama as daqui.
module FechamentoAutomacao::SondasDoRegistroLigado
  extend CrmHelpers

  module_function

  # G18: o passo "em outro registro" da mãe lê no alvo dela o contato guardado no campo, e o job abre a execução filha no
  # contato ligado, que anda só no ramo do passo (nunca nos passos da mãe). Roda na transação do exemplo, que desfaz
  # tudo; a primeira rodada da filha só fica na fila.
  def filha_anda_no_registro_ligado?
    filha = filha_na_maria
    roteiro = filha && Autonomia::Automacao::Roteiro.da(filha)
    roteiro.present? && roteiro.primeiro['id'] == 'na_maria' && roteiro.seguinte('na_maria').nil?
  end

  # G65: a filha, na Maria, lê o nome do João no registro de origem, como o Executor lê.
  def filha_le_a_origem?
    filha = filha_na_maria
    contexto = filha && Autonomia::Automacao::Contexto.de(filha.alvo, execucao: filha)
    lido = contexto && Autonomia::Automacao::Valores.new(alvo: contexto, quem: filha.automacao.ligada_por).ler('origem.contato.nome')
    lido == 'João'
  end

  # A execução filha aberta na Maria pelo passo da mãe, que roda no card do João (quem ela indicou). A Maria fica no
  # campo do card do tipo contato (decisão 16). O gatilho de card pede a flag dos gatilhos e o CRM ligado.
  def filha_na_maria
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      account = FactoryBot.create(:account)
      account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
      FactoryBot.create(:custom_attribute_definition, account: account, attribute_key: 'indicado_por', attribute_display_name: 'Indicado por',
                                                      attribute_model: 'card_attribute', attribute_display_type: 'contato')
      maria = account.contacts.create!(name: 'Maria')
      dona = FactoryBot.create(:user, account: account, role: :administrator)
      mae = mae_com_passo_em_outro(account, card_do_joao(account, dona, maria), dona)
      abrir_filhas(mae) && Autonomia::Automacao::Execucao.find_by(automacao_id: mae.automacao_id, alvo: maria)
    end
  end

  def card_do_joao(account, dona, maria)
    funil, etapa = create_crm_pipeline(account: account, user: dona)
    account.crm_cards.create!(pipeline: funil, stage: etapa, contact: account.contacts.create!(name: 'João'), title: 'Banho do Rex',
                              currency: 'BRL', custom_attributes: { 'indicado_por' => maria.id })
  end

  def mae_com_passo_em_outro(account, card, dona)
    ramo = { 'id' => 'na_maria', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }
    passo = { 'id' => 'outro', 'tipo' => 'em_outro_registro', 'passos' => [ramo],
              'registro' => { 'de' => 'contato_do_campo', 'campo' => { '$valor' => 'card.atributos.indicado_por' }, 'usar' => 'contato' } }
    receita = { 'gatilho' => { 'tipo' => 'card.ganho' }, 'passos' => [passo, { 'id' => 'na_mae', 'tipo' => 'parar' }] }
    automacao = FactoryBot.create(:autonomia_automacao, account: account, ativa: true, ligada_por: dona)
    versao = FactoryBot.create(:autonomia_automacao_versao, automacao: automacao, receita: receita)
    FactoryBot.create(:autonomia_automacao_execucao, versao: versao, alvo: card)
  end

  # O passo da mãe como o Executor o roda, e o job que ele enfileira, com o contato que o passo leu.
  def abrir_filhas(mae)
    passo = Autonomia::Automacao::Roteiro.da(mae).passo('outro')
    valores = Autonomia::Automacao::Valores.new(alvo: mae.alvo, quem: mae.automacao.ligada_por)
    acesso = Autonomia::Automacao::Acesso.new(mae.automacao, chave_gatilho: mae.chave_gatilho)
    lido = Autonomia::Automacao::PassoEmOutroRegistro.new(execucao: mae, passo: passo, valores: valores, acesso: acesso).executar
    return false unless lido.tipo == :ok

    Autonomia::Automacao::EmOutroRegistroJob.perform_now(mae.account_id, mae.id, 'outro', lido.dados['contato_id'])
    true
  end
end
