# A sonda da G69 (#2879, exemplo 16, passo 6: "grava um retorno para daqui a 11 meses"), por comportamento: o passo
# "criar retorno" com `daqui` em meses cria o retorno de verdade (PassoDeRetorno, pela porta da ação), com o vencimento
# contado no calendário e no fuso da conta. A conta fica em Tóquio e o relógio em 31/01 às 8h de lá (30/01 no UTC): pelo
# calendário da conta, 1 mês vence em 28/02 às 8h; pelo do servidor, cairia em 01/03. Fica fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a daqui. Roda na transação do
# exemplo, que desfaz tudo.
module FechamentoAutomacao::SondasDoRetorno
  extend CrmHelpers
  extend ActiveSupport::Testing::TimeHelpers

  module_function

  TOQUIO = ActiveSupport::TimeZone['Asia/Tokyo']

  def retorno_em_meses_no_calendario_da_conta?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      account = FactoryBot.create(:account, custom_attributes: { 'timezone' => TOQUIO.name })
      account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
      dona = FactoryBot.create(:user, account: account, role: :administrator)
      execucao = execucao_no_card(account, dona)
      travel_to(TOQUIO.local(2026, 1, 31, 8)) { criar_retorno(execucao, dona) }
      Crm::FollowUp.find_by(card: execucao.alvo)&.due_at == TOQUIO.local(2026, 2, 28, 8)
    end
  end

  def passo = { 'id' => 'g69', 'tipo' => 'retorno', 'titulo' => ['Sonda G69'], 'daqui' => { 'valor' => 1, 'unidade' => 'meses' } }

  def execucao_no_card(account, dona)
    funil, etapa = create_crm_pipeline(account: account, user: dona)
    card = account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Sonda G69', currency: 'BRL', owner: dona)
    receita = { 'gatilho' => { 'tipo' => 'card.ganho' }, 'passos' => [passo] }
    automacao = FactoryBot.create(:autonomia_automacao, account: account, ligada_por: dona)
    versao = FactoryBot.create(:autonomia_automacao_versao, automacao: automacao, receita: receita)
    FactoryBot.create(:autonomia_automacao_execucao, versao: versao, alvo: card, chave_gatilho: 'card.ganho')
  end

  def criar_retorno(execucao, dona)
    definicao = execucao.automacao
    valores = Autonomia::Automacao::Valores.new(alvo: Autonomia::Automacao::Contexto.de(execucao.alvo, execucao: execucao), quem: dona)
    acesso = Autonomia::Automacao::Acesso.new(definicao, chave_gatilho: execucao.chave_gatilho)
    Autonomia::Automacao::PassoDeRetorno.new(execucao: execucao, passo: passo, valores: valores, acesso: acesso).executar
  end
end
