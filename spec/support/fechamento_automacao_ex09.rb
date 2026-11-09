# As sondas da G21 e da G58, do exemplo 9 (#2414 F9): roda o código de verdade e confere o efeito. Fica fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a daqui.
module FechamentoAutomacao::SondasDoExemplo9
  extend CrmHelpers

  module_function

  # G21 (#2706): o passo "prospecção" do gatilho da conta roda a busca do histórico e cria o card da empresa com WhatsApp.
  # Roda o passo de verdade, com o provedor de teste da Prospecção (MockProvider: nunca chama o Google), e dá a
  # conferência de WhatsApp como feita entre a primeira rodada (busca e espera) e a segunda (cria o card). Roda na
  # transação do exemplo, que desfaz tudo.
  def prospeccao_cria_o_card?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true', WAHA_API_URL: 'https://waha.sonda.test', WAHA_API_KEY: 'sonda-g21') do
      account, dona, etapa = conta_da_prospeccao
      origem = Autonomia::Prospecting::SearchRunner.new(account: account, user: dona,
                                                        params: { query: 'contabilidade', location: 'Campinas, SP',
                                                                  requested_limit: 1 }).perform.search
      passo = { 'id' => 'p1', 'tipo' => 'prospeccao', 'faz' => 'buscar', 'busca_id' => origem.id, 'quantas' => 1,
                'etapa_id' => etapa.id, 'etiquetas' => [] }
      buscar_e_conferir(account, dona, passo)
      account.crm_cards.exists?(stage: etapa)
    end
  end

  # G58 (#2779): o público `desta_execucao` é só quem a busca desta execução criou. O registro do passo é gravado com os
  # dados que a busca de verdade devolve (os `card_ids` do BuscaDaProspeccao), como o executor grava; o contato que já
  # existia na conta não entra. Roda na transação do exemplo, que desfaz tudo.
  def publico_so_dos_criados?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true', WAHA_API_URL: 'https://waha.sonda.test', WAHA_API_KEY: 'sonda-g58') do
      account, dona, etapa = conta_da_prospeccao
      antigo = FactoryBot.create(:contact, account: account, phone_number: '+5511900000058')
      execucao, resultado = buscar_e_registrar(account, dona, etapa)
      criados = account.crm_cards.where(id: resultado.dados['card_ids']).pluck(:contact_id)
      publico = Autonomia::Automacao::ContatosDaExecucao.new(execucao: execucao).dentro.map(&:id)
      criados.any? && publico.sort == criados.sort && publico.exclude?(antigo.id)
    end
  end

  def buscar_e_registrar(account, dona, etapa)
    origem = Autonomia::Prospecting::SearchRunner.new(account: account, user: dona,
                                                      params: { query: 'contabilidade', location: 'Campinas, SP',
                                                                requested_limit: 2 }).perform.search
    passo = { 'id' => 'p1', 'tipo' => 'prospeccao', 'faz' => 'buscar', 'busca_id' => origem.id, 'quantas' => 2,
              'etapa_id' => etapa.id, 'etiquetas' => [] }
    execucao, resultado = buscar_e_conferir(account, dona, passo)
    Autonomia::Automacao::Registro.create!(account: account, automacao: execucao.automacao, execucao: execucao, passo: passo['id'],
                                           resultado: resultado.tipo.to_s, motivo: resultado.motivo, dados: resultado.dados)
    [execucao, resultado]
  end

  def conta_da_prospeccao
    account = FactoryBot.create(:account)
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
    dona = FactoryBot.create(:user, account: account, role: :administrator)
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock')
    # O número que a Prospecção usa para conferir WhatsApp (WhatsappVerifier.session_for).
    FactoryBot.create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'sonda-g21' })
    [account, dona, create_crm_pipeline(account: account, user: dona).last]
  end

  def buscar_e_conferir(account, dona, passo)
    definicao = FactoryBot.create(:autonomia_automacao, account: account, ligada_por: dona)
    gatilho = { 'tipo' => 'conta.recorrente', 'frequencia' => 'semanal', 'dia_da_semana' => 1, 'hora' => 8 }
    definicao.salvar_versao!(receita: { 'gatilho' => gatilho, 'passos' => [passo] }, autor: dona)
    definicao.update!(ativa: true)
    execucao = Autonomia::Automacao::Partida.new(definicao: definicao, alvo: account, chave_gatilho: 'conta.recorrente').call
    rodar_o_passo(execucao, passo)
    Autonomia::Prospecting::Lead.where(account: account).find_each do |lead|
      lead.update!(metadata: lead.metadata.to_h.merge('whatsapp_verification' => { 'status' => 'verified' }))
    end
    [execucao, rodar_o_passo(execucao, passo)]
  end

  def rodar_o_passo(execucao, passo)
    acesso = Autonomia::Automacao::Acesso.new(execucao.automacao)
    Autonomia::Automacao::PassoDeAcao.executar(execucao: execucao, passo: passo, valores: nil, acesso: acesso)
  end
end
