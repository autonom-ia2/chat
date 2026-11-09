# As sondas da G24 e da G22, do exemplo 8 (#2414 F9): roda o código de verdade e confere o efeito. Fica fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama a daqui.
module FechamentoAutomacao::SondasDoExemplo8
  extend CrmHelpers

  module_function

  # G24: a 1ª automação abre um card por item da lista ("para cada item"), e a 2ª, de card criado, roda em cada card. A
  # lista já guardada na execução não vai à IA. Os jobs do caminho rodam um por vez, na transação do exemplo.
  def segunda_automacao_em_cada_card?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') do
      account, admin, funil, etapa = conta_da_sonda_g24
      lista = automacao_da_sonda(account, admin, { 'tipo' => 'conversa.resolvida' }, [para_cada_da_sonda(etapa)])
      em_cada_card = automacao_da_sonda(account, admin, { 'tipo' => 'card.criado', 'funil_id' => funil.id }, [{ 'id' => 'fim', 'tipo' => 'parar' }])
      conversa = FactoryBot.create(:conversation, account: account)
      Autonomia::Automacao::Partida.new(definicao: lista, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
                                   &.guardar_texto!('lista.itens', [{ 'nome' => 'Sonda Um' }, { 'nome' => 'Sonda Dois' }])
      rodar_jobs_da_sonda
      cards = funil.cards.order(:id).to_a
      cards.size == 2 && Autonomia::Automacao::Execucao.where(automacao: em_cada_card).order(:id).map(&:alvo) == cards
    end
  end

  def conta_da_sonda_g24
    account = FactoryBot.create(:account)
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_ia', 'automacao_gatilhos')
    admin = FactoryBot.create(:user, account: account, role: :administrator)
    [account, admin, *create_crm_pipeline(account: account, user: admin)]
  end

  def automacao_da_sonda(account, admin, gatilho, passos)
    definicao = FactoryBot.create(:autonomia_automacao, account: account, ligada_por: admin)
    definicao.salvar_versao!(receita: { 'gatilho' => gatilho, 'passos' => passos }, autor: admin)
    definicao.update!(ativa: true)
    definicao
  end

  def para_cada_da_sonda(etapa)
    { 'id' => 'lista', 'tipo' => 'para_cada', 'le' => %w[mensagens_recentes], 'descricao' => 'Cada pessoa da lista',
      'campos' => [{ 'chave' => 'nome', 'descricao' => 'Nome' }], 'etapa_id' => etapa.id, 'maximo' => 10 }
  end

  JOBS_DA_SONDA = %w[Autonomia::Automacao::AvancarJob EventDispatcherJob Autonomia::Automacao::EventoDoCardJob].freeze

  def rodar_jobs_da_sonda
    fila = ActiveJob::Base.queue_adapter.enqueued_jobs
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = fila.find { |item| JOBS_DA_SONDA.include?(item[:job].to_s) }
      return unless job

      fila.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end

  # G22 (exemplo 8, passo 9): o RH que pediu dois cards, um completo e um sem o CPF. A seleção do contato.recorrente
  # pega o RH, e o valor lista só quem falta, com o que falta. Roda na transação do exemplo, que desfaz tudo. Fora do
  # SONDAS enquanto a G22 está desligada: volta para lá quando o "para cada item" gravar o solicitante.
  def rh_avisado_do_que_falta?
    rh, contexto, selecao = rh_com_dois_pedidos
    Autonomia::Automacao::Tempo::Selecao.new(rh.account, { 'tipo' => 'contato.recorrente', 'selecao' => selecao })
                                        .escopo_para(contexto, pergunta: :update?)&.pluck(:id) == [rh.id] &&
      Autonomia::Automacao::Valores::DA_SELECAO.fetch('contato.solicitados_faltando')
                                               .call(rh, contexto[:account_user], selecao) == 'Bia (CPF)'
  end

  # O RH da Acme pediu os cards da Ana (RG e CPF marcados) e da Bia (só o RG), no funil "Inclusão de vidas".
  def rh_com_dois_pedidos
    account = FactoryBot.create(:account)
    dona = FactoryBot.create(:user, account: account, role: :administrator)
    funil = account.crm_pipelines.create!(name: 'Inclusão de vidas', created_by: dona, status: :active)
    etapa = account.crm_pipeline_stages.create!(pipeline: funil, name: 'Documentos', position: 0)
    %w[rg cpf].each do |chave|
      FactoryBot.create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave.upcase,
                                                      attribute_model: 'card_attribute', attribute_display_type: 'checkbox')
    end
    rh = FactoryBot.create(:contact, account: account, name: 'RH da Acme')
    { 'Ana' => { 'rg' => true, 'cpf' => true }, 'Bia' => { 'rg' => true } }.each do |nome, marcados|
      account.crm_cards.create!(pipeline: funil, stage: etapa, title: nome, currency: 'BRL', solicitante: rh, custom_attributes: marcados,
                                contact: FactoryBot.create(:contact, account: account, name: nome))
    end
    [rh, { user: dona, account: account, account_user: account.account_users.find_by(user: dona) },
     { 'solicitante_de' => { 'funil_id' => funil.id, 'faltando' => %w[rg cpf] } }]
  end
end
