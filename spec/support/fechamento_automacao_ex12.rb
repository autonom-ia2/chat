# A sonda da G48, do exemplo 12 (#2414 F9): roda o código de verdade e confere o efeito. Fica fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a daqui.
module FechamentoAutomacao::SondasDoExemplo12
  extend CrmHelpers

  module_function

  # G48: uma execução espera até o campo do card ser preenchido; o card grava o campo, e o gancho do modelo
  # (Crm::CardAvisaAutomacao, depois do commit) a tira da espera na hora, sem a varredura do relógio. Roda na transação
  # do exemplo, que desfaz tudo; o AvancarJob só fica na fila.
  def campo_do_card_acorda_a_espera?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      account = FactoryBot.create(:account)
      account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
      FactoryBot.create(:custom_attribute_definition, account: account, attribute_key: 'como_foi', attribute_display_name: 'Como foi',
                                                      attribute_model: 'card_attribute', attribute_display_type: 'text')
      funil, etapa = create_crm_pipeline(account: account, user: FactoryBot.create(:user, account: account, role: :administrator))
      card = account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Sonda G48', currency: 'BRL')
      execucao = esperando_o_campo_como_foi(card, etapa)
      card.update!(custom_attributes: { 'como_foi' => 'Gostou' })
      execucao.reload.estado != 'esperando'
    end
  end

  def esperando_o_campo_como_foi(card, etapa)
    espera = { 'id' => 'espera', 'tipo' => 'esperar_ate', 'prazo' => { 'valor' => 1, 'unidade' => 'horas' },
               'condicao' => { 'campo' => { '$valor' => 'card.atributos.como_foi' }, 'op' => 'preenchido' } }
    receita = { 'gatilho' => { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => etapa.id }, 'passos' => [espera] }
    automacao = FactoryBot.create(:autonomia_automacao, account: card.account)
    versao = FactoryBot.create(:autonomia_automacao_versao, automacao: automacao, receita: receita)
    FactoryBot.create(:autonomia_automacao_execucao, versao: versao, alvo: card, estado: 'esperando', cursor: 'espera',
                                                     due_at: 1.hour.from_now)
  end
end
