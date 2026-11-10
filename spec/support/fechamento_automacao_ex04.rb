# A sonda da G50, do exemplo 4 (#2414 F9): roda o código de verdade e confere o efeito. Fica fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a daqui.
module FechamentoAutomacao::SondasDoExemplo04
  extend CrmHelpers

  module_function

  # G50: o card entra de novo em "Faltou" com a 1ª execução esperando "não entrou de novo em 30 dias". Tudo pelo caminho
  # real (o Crm::Cards::Mover grava a atividade, o emissor do CRM despacha, a Partida começa e o Despertador acorda), com
  # os jobs rodando um por vez. Na nova entrada, o evento roda antes da rodada da 1ª, que segue aberta (o Despertador já
  # a reservou no commit do card): sem `se_repetir`, a Partida não abriria outra. Nasce a 2ª execução no mesmo card,
  # esperando; e a 1ª acha a nova entrada e conclui, com o segundo "ok" no passo da espera (o primeiro é o começo dela).
  def nova_entrada_comeca_outra_e_acorda_a_espera?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      card, faltou, ativo, admin = card_da_sonda
      automacao_da_sonda(card, faltou, admin)
      [faltou, ativo].each { |etapa| mover_e_rodar(card, etapa, admin) }
      mover_e_rodar(card, faltou, admin, evento_antes: true)
      comecou_outra_e_a_primeira_concluiu?(card)
    end
  # Sem a G50, o esquema da versão recusa `se_repetir` no gatilho: a lacuna está aberta. Qualquer outro erro sobe: sonda
  # quebrada não vira pendente.
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.is_a?(Autonomia::Automacao::Versao) && e.record.errors.attribute_names.include?(:'gatilho/se_repetir')

    false
  end

  def comecou_outra_e_a_primeira_concluiu?(card)
    primeira, segunda = Autonomia::Automacao::Execucao.where(alvo: card).order(:id).to_a
    passos_da_primeira = Autonomia::Automacao::Registro.where(execucao: primeira, passo: 'espera').order(:id).pluck(:resultado, :motivo)
    segunda&.estado == 'esperando' && primeira&.estado == 'concluida' && passos_da_primeira == [['ok', nil], ['ok', nil]]
  end

  def card_da_sonda
    account = FactoryBot.create(:account)
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
    admin = FactoryBot.create(:user, account: account, role: :administrator)
    funil, ativo = create_crm_pipeline(account: account, user: admin)
    faltou = create_crm_stage(account: account, pipeline: funil, name: 'Faltou')
    [account.crm_cards.create!(pipeline: funil, stage: ativo, title: 'Sonda G50', currency: 'BRL'), faltou, ativo, admin]
  end

  def automacao_da_sonda(card, etapa, quem)
    espera = { 'id' => 'espera', 'tipo' => 'esperar_ate', 'prazo' => { 'valor' => 30, 'unidade' => 'dias' },
               'condicao' => { 'campo' => { '$valor' => 'card.entrou_de_novo' }, 'op' => 'igual', 'valor' => true } }
    gatilho = { 'tipo' => 'card.entrou_na_etapa', 'etapa_id' => etapa.id, 'se_repetir' => 'comeca_outra' }
    automacao = FactoryBot.create(:autonomia_automacao, account: card.account, ligada_por: quem)
    automacao.salvar_versao!(receita: { 'gatilho' => gatilho, 'passos' => [espera] }, autor: quem)
    automacao.update!(ativa: true)
  end

  # `evento_antes`: o despacho e o evento do card rodam antes da rodada (AvancarJob) que o Despertador enfileirou.
  def mover_e_rodar(card, etapa, quem, evento_antes: false)
    Crm::Cards::Mover.new(card: card.reload, actor: quem, target_stage: etapa).perform
    rodar_o_evento if evento_antes
    FechamentoAutomacao::SondasDoExemplo8.rodar_jobs_da_sonda
  end

  JOBS_DO_EVENTO = %w[EventDispatcherJob Autonomia::Automacao::EventoDoCardJob].freeze

  def rodar_o_evento
    fila = ActiveJob::Base.queue_adapter.enqueued_jobs
    while (job = fila.find { |item| JOBS_DO_EVENTO.include?(item[:job].to_s) })
      fila.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end
end
