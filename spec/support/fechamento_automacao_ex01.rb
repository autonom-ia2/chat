# A sonda da G57, do exemplo 1 (#2414 F9): roda o código de verdade e confere o efeito. Fica fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a daqui.
module FechamentoAutomacao::SondasDoExemplo1
  extend ActiveSupport::Testing::TimeHelpers

  module_function

  FUSO = 'America/Sao_Paulo'.freeze

  # G57 (#2769, ex. 1, passo 7): o retorno "hoje às 9h", salvo e rodado pelo motor às 10h no fuso da conta, vence em
  # seguida (agora), nunca amanhã. Roda na transação do exemplo, que desfaz tudo.
  def hora_de_hoje_que_passou_vence_agora?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      account = FactoryBot.create(:account, custom_attributes: { 'timezone' => FUSO })
      account.enable_features!('automacao_fundacao', 'automacao_motor')
      dona = FactoryBot.create(:user, account: account, role: :administrator)
      agora = ActiveSupport::TimeZone[FUSO].local(2026, 11, 9, 10)
      travel_to(agora) { rodar_o_retorno(account, dona, retorno_de_hoje(dona, 9)) }
      Crm::FollowUp.find_by(account_id: account.id)&.due_at == agora
    end
  end

  def retorno_de_hoje(dona, hora)
    { 'id' => 'retorno', 'tipo' => 'retorno', 'titulo' => ['Sonda G57'], 'quando' => { 'dia' => 'hoje', 'hora' => hora },
      'para' => { 'quem' => 'pessoas', 'pessoas' => [dona.id] } }
  end

  # Salva a receita, liga e roda a execução numa conversa da conta, como o gatilho faria.
  def rodar_o_retorno(account, dona, passo)
    definicao = FactoryBot.create(:autonomia_automacao, account: account, ligada_por: dona)
    definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }, autor: dona)
    definicao.update!(ativa: true)
    conversa = FactoryBot.create(:conversation, account: account)
    Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
    FechamentoAutomacao::SondasDoExemplo8.rodar_jobs_da_sonda
  end
end
