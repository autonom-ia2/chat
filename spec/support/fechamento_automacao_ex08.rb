# As sondas da G24 e da G22, do exemplo 8 (#2414 F9): rodam o código de verdade e conferem o efeito. Ficam fora do
# FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama as daqui.
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

  # G22 (exemplo 8, passo 9): o RH manda a lista e o "para cada item" do motor abre os cards da Ana e da Bia, cada um
  # com o RH de solicitante. A Ana manda tudo e a Bia só o RG. A seleção do contato.recorrente pega o RH, e o valor
  # lista só quem falta, com o que falta. Os jobs do caminho rodam um por vez, na transação do exemplo, que desfaz tudo.
  def rh_avisado_do_que_falta?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') do
      account, admin, funil, etapa = conta_da_sonda_g24
      rh = pedidos_do_rh(account, admin, etapa)
      cards = funil.cards.order(:id).to_a
      next false unless cards.map(&:solicitante_contact_id) == [rh.id, rh.id]

      cards.first.update!(custom_attributes: { 'rg' => true, 'cpf' => true })
      cards.last.update!(custom_attributes: { 'rg' => true })
      lista_ao_rh(rh, admin, { 'solicitante_de' => { 'funil_id' => funil.id, 'faltando' => %w[rg cpf] } }) == 'Bia (CPF)'
    end
  end

  # O RH da Acme manda a lista na conversa dele; a lista já guardada na execução não vai à IA.
  def pedidos_do_rh(account, admin, etapa)
    %w[rg cpf].each do |chave|
      FactoryBot.create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave.upcase,
                                                      attribute_model: 'card_attribute', attribute_display_type: 'checkbox')
    end
    lista = automacao_da_sonda(account, admin, { 'tipo' => 'conversa.resolvida' }, [para_cada_da_sonda(etapa)])
    rh = FactoryBot.create(:contact, account: account, name: 'RH da Acme')
    conversa = FactoryBot.create(:conversation, account: account, contact: rh)
    Autonomia::Automacao::Partida.new(definicao: lista, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
                                 &.guardar_texto!('lista.itens', [{ 'nome' => 'Ana' }, { 'nome' => 'Bia' }])
    rodar_jobs_da_sonda
    rh
  end

  # A seleção do contato.recorrente e o valor que vai ao RH, como quem ligou.
  def lista_ao_rh(contato_do_rh, admin, selecao)
    contexto = { user: admin, account: contato_do_rh.account, account_user: contato_do_rh.account.account_users.find_by(user: admin) }
    escolhidos = Autonomia::Automacao::Tempo::Selecao.new(contato_do_rh.account, { 'tipo' => 'contato.recorrente', 'selecao' => selecao })
                                                     .escopo_para(contexto, pergunta: :update?)&.pluck(:id)
    return unless escolhidos == [contato_do_rh.id]

    Autonomia::Automacao::Valores::DA_SELECAO.fetch('contato.solicitados_faltando').call(contato_do_rh, contexto[:account_user], selecao)
  end
end
