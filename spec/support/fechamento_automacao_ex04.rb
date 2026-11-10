# A sonda da G50, do exemplo 4 (#2414 F9): roda o código de verdade e confere o efeito. Fica fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a daqui.
module FechamentoAutomacao::SondasDoExemplo04
  extend CrmHelpers

  module_function

  # G50: o card entra de novo em "Faltou" com a 1ª execução esperando "não entrou de novo em 30 dias". A sonda pergunta
  # o comportamento, pelo caminho real (Mover grava a atividade; a Escuta recebe o evento dela): nasce a 2ª execução no
  # mesmo card, e a 1ª é reservada para conferir a condição agora.
  def nova_entrada_comeca_outra_e_acorda_a_espera?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      account = FactoryBot.create(:account)
      account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
      admin = FactoryBot.create(:user, account: account, role: :administrator)
      funil, ativo = create_crm_pipeline(account: account, user: admin)
      faltou = create_crm_stage(account: account, pipeline: funil, name: 'Faltou')
      card = account.crm_cards.create!(pipeline: funil, stage: ativo, title: 'Sonda G50', currency: 'BRL')
      primeira = esperando_a_nova_entrada(card, faltou, admin)
      Crm::Cards::Mover.new(card: card, actor: admin, target_stage: faltou).perform
      entregar_a_entrada(card)
      Autonomia::Automacao::Execucao.where(alvo: card).count == 2 && primeira.reload.estado != 'esperando'
    end
  # Sem a G50, o esquema recusa o `se_repetir` ao salvar: a lacuna está aberta.
  rescue ActiveRecord::RecordInvalid
    false
  end

  def esperando_a_nova_entrada(card, etapa, quem)
    espera = { 'id' => 'espera', 'tipo' => 'esperar_ate', 'prazo' => { 'valor' => 30, 'unidade' => 'dias' },
               'condicao' => { 'campo' => { '$valor' => 'card.entrou_de_novo' }, 'op' => 'igual', 'valor' => true } }
    gatilho = { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => etapa.id, 'se_repetir' => 'comeca_outra' }
    automacao = FactoryBot.create(:autonomia_automacao, account: card.account, ligada_por: quem)
    automacao.salvar_versao!(receita: { 'gatilho' => gatilho, 'passos' => [espera] }, autor: quem)
    automacao.update!(ativa: true)
    FactoryBot.create(:autonomia_automacao_execucao, versao: automacao.versao_ativa, alvo: card, chave_gatilho: gatilho['tipo'],
                                                     estado: 'esperando', cursor: 'espera', due_at: 30.days.from_now - 1.minute)
  end

  # O evento que o emissor do CRM despacha para a atividade do movimento, entregue à Escuta como o EventoDoCardJob faz.
  def entregar_a_entrada(card)
    atividade = Crm::Activity.where(card_id: card.id, event_type: 'move').order(:id).last
    dados = { account_id: card.account_id, card_id: card.id, activity_id: atividade.id, changed_attributes: atividade.payload }
    Autonomia::Automacao::Escuta.evento_do_card(dados, Events::Types::CRM_CARD_MOVED)
  end
end
