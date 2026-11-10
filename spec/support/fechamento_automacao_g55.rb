# A sonda da G55 (exemplo 16, passo 2), por comportamento: no card.recorrente, a campanha da etiqueta é uma só para a
# vez inteira. Roda a CampanhaDaOcorrencia de verdade, como em spec/fechamento/automacao/g55_campanha_no_card_spec.rb: a
# varredura abre a vez, dois cards chegam ao passo, e a campanha nasce uma vez, só quando o último chega. Fica fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a daqui. Roda na transação do
# exemplo, que desfaz tudo; o disparo só fica na fila.
module FechamentoAutomacao::SondasDaCampanhaDaVez
  extend CrmHelpers

  module_function

  GATILHO = { 'tipo' => 'card.recorrente', 'frequencia' => 'mensal', 'dia_do_mes' => 1, 'hora' => 9,
              'selecao' => { 'situacao' => 'perdido' } }.freeze
  MODELO = { 'name' => 'seguro_vencendo', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
             'components' => [{ 'type' => 'BODY', 'text' => 'Seu seguro está vencendo. {{1}}' }] }.freeze

  def uma_campanha_por_vez?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      canal = FactoryBot.create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      account = preparar(canal)
      dona = FactoryBot.create(:user, account: account, role: :administrator)
      passo = disparar(canal, FactoryBot.create(:label, account: account, title: 'reconquista'))
      definicao = ligada(account, dona, passo)
      execucoes = cards(account, dona).map { |card| execucao(definicao, card) }
      chegadas_fecham_a_vez_uma_vez?(definicao, passo, execucoes)
    end
  end

  def preparar(canal)
    account = canal.account
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens', 'automacao_gatilhos', 'whatsapp_campaign')
    canal.update!(message_templates: [MODELO])
    account
  end

  def disparar(canal, etiqueta)
    { 'id' => 'campanha', 'tipo' => 'campanha', 'faz' => 'disparar', 'titulo' => 'Seu seguro está vencendo', 'caixa_id' => canal.inbox.id,
      'modelo' => { 'nome' => 'seguro_vencendo', 'idioma' => 'pt_BR', 'variaveis' => [['Este ano consigo melhor.']] },
      'etiquetas' => [etiqueta.id] }
  end

  def ligada(account, dona, passo)
    definicao = FactoryBot.create(:autonomia_automacao, account: account, ligada_por: dona)
    definicao.salvar_versao!(receita: { 'gatilho' => GATILHO, 'passos' => [passo] }, autor: dona)
    definicao.update!(ativa: true)
    definicao
  end

  def cards(account, dona)
    funil, etapa = create_crm_pipeline(account: account, user: dona)
    Array.new(2) do
      contato = FactoryBot.create(:contact, account: account)
      account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Sonda G55', currency: 'BRL', contact: contato, status: :lost)
    end
  end

  def vez = Time.zone.parse('2026-11-01 12:00:00 UTC')

  def execucao(definicao, card)
    Autonomia::Automacao::Execucao.create!(automacao: definicao, account: definicao.account, versao: definicao.versao_ativa, alvo: card,
                                           chave_gatilho: 'card.recorrente',
                                           evento: Autonomia::Automacao::Gatilhos.marca_do_recorrente('card.recorrente', card.id, vez))
  end

  # A varredura abre a vez e conta o lote; cada card chega ao passo como no Executor (o passo, o registro, a conferência).
  # Antes do último: nenhuma campanha. Depois: uma só, para a etiqueta, e a vez fechada com ela.
  def chegadas_fecham_a_vez_uma_vez?(definicao, passo, execucoes)
    linha = varredura(definicao)
    antes = chegar(passo, execucoes.first) && definicao.account.campaigns.none?
    chegar(passo, execucoes.last)
    campanhas = definicao.account.campaigns.to_a
    antes && campanhas.size == 1 && campanhas.first.audience == [{ 'type' => 'Label', 'id' => passo['etiquetas'].first }] &&
      linha.reload.campanha_display_id == campanhas.first.display_id
  end

  def varredura(definicao)
    ocorrencia = Autonomia::Automacao::CampanhaDaOcorrencia
    linha = ocorrencia.abrir(definicao, vez).sole
    ocorrencia.lotes([linha], 1)
    ocorrencia.lote_feito(definicao, 'card.recorrente', vez, 0)
    linha
  end

  def chegar(passo, execucao)
    resultado = Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: passo, alvo: execucao.alvo).executar
    Autonomia::Automacao::Registro.create!(account: execucao.account, automacao: execucao.automacao, execucao: execucao, passo: passo['id'],
                                           resultado: 'ok', motivo: resultado.motivo, dados: resultado.dados)
    Autonomia::Automacao::CampanhaDaOcorrencia.conferir_execucao(execucao)
    resultado.motivo == Autonomia::Automacao::CampanhaDaOcorrencia::AGUARDANDO
  end
end
