# O teste de fechamento da Automação livre (#2414 F9.6 a F9.8, #2570). Desenho em
# docs/automacao/F9-fechamento-20-exemplos.md.
#
# - A automação é montada e ligada pela API pública da tela, como o dono faria.
# - O gatilho chega pelo despacho da plataforma: os jobs rodam um por vez, como no Sidekiq.
# - O que sai da plataforma passa inteiro pelo nosso código e para no receptor, na camada HTTP, que grava o pedido.
# - A IA é um dublê no endereço da OpenAI: o PassoDeIa roda inteiro (chave da conta, schema, custo).
# - As esperas andam com o relógio adiantado e a varredura do motor.
module FechamentoAutomacao
  OPENAI = 'https://api.openai.com/v1/responses'.freeze
  # Os jobs que o caminho de produção enfileira entre o evento e a saída. Os do webhook de cada canal (FechamentoAutomacao::
  # Canais) gravam a mensagem do cliente como em produção. O EmOutroRegistroJob (G18) abre as execuções filhas do passo
  # "em outro registro".
  JOBS = [Webhooks::WhatsappEventsJob, Webhooks::InstagramEventsJob, EventDispatcherJob, Autonomia::Automacao::AvancarJob,
          Autonomia::Automacao::EmOutroRegistroJob, SendReplyJob].freeze
  LIMITE_DE_JOBS = 60

  Chamada = Data.define(:metodo, :host, :caminho, :corpo)

  def flags_do_piloto(account)
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens', 'automacao_ia', 'automacao_editor')
  end

  def api_automacoes(account) = "/api/v1/accounts/#{account.id}/autonomia/automacoes"

  # POST da tela. Devolve o corpo da resposta; o spec confere o 201.
  def montar_automacao(dono, account, nome:, receita:)
    post api_automacoes(account), params: { nome: nome, receita: receita }, headers: dono.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created), -> { "a automação não foi criada: #{response.body}" }
    response.parsed_body
  end

  def ligar_automacao(dono, account, automacao)
    post "#{api_automacoes(account)}/#{automacao['id']}/ligar",
         params: { versao_id: automacao.dig('versao', 'id') }, headers: dono.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), -> { "a automação não ligou: #{response.body}" }
    expect(response.parsed_body['ativa']).to be(true)
  end

  # A mensagem do cliente gravada como o canal grava: o callback do modelo dispara o evento, e os jobs seguem.
  def cliente_escreve(conversa, texto)
    create(:message, conversation: conversa, account: conversa.account, inbox: conversa.inbox, message_type: :incoming,
                     sender: conversa.contact, content: texto)
    rodar_jobs
  end

  # Um job por vez, como no Sidekiq: o enfileirado dentro de outro roda depois dele. Os outros jobs ficam na fila; se o
  # spec não achar o que esperava, `jobs_fora` diz quais ficaram sem rodar.
  def rodar_jobs
    LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| JOBS.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{LIMITE_DE_JOBS} jobs" if enqueued_jobs.any? { |item| JOBS.include?(item[:job]) }
  end

  def jobs_fora = enqueued_jobs.map { |item| item[:job].name }.uniq

  def receptor = (@receptor ||= [])

  # O WhatsApp oficial: o SendReplyJob chama a Graph de verdade, e o receptor grava o pedido (F9.7).
  def receptor_whatsapp_cloud
    stub_request(:post, ->(uri) { uri.host == 'graph.facebook.com' }).to_return do |pedido|
      receptor << Chamada.new(metodo: 'POST', host: pedido.uri.host, caminho: pedido.uri.path, corpo: JSON.parse(pedido.body))
      { status: 200, body: { messages: [{ id: "wamid.F9#{receptor.size}" }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def chamadas_para(host) = receptor.select { |chamada| chamada.host == host }

  # A IA com a chave da conta (D2 B), respondida pelo dublê. `roteiro`: { 'automacao_decidir' => {...},
  # 'automacao_resumir' => {...} }, a resposta escolhida pelo nome do schema que o passo mandou. O que a IA recebeu fica
  # em `ia_recebeu`.
  def ia_responde(account, roteiro)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    stub_request(:post, OPENAI).to_return do |pedido|
      corpo = JSON.parse(pedido.body)
      ia_recebeu << corpo
      resposta = roteiro.fetch(corpo.dig('text', 'format', 'name'))
      payload = { id: "resp_#{ia_recebeu.size}", output_text: resposta.to_json, usage: { input_tokens: 800, output_tokens: 120 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def ia_recebeu = (@ia_recebeu ||= [])

  def historico_de(automacao)
    Autonomia::Automacao::Registro.where(automacao_id: automacao['id']).order(:id).pluck(:passo, :resultado, :motivo)
  end
end

# As sondas de comportamento do placar: cada uma monta o cenário mínimo, roda o caminho de produção e confere o efeito,
# em vez de só procurar o nome no esquema. Lacuna aberta responde false, nunca erro.
module FechamentoAutomacao::Comportamento
  extend CrmHelpers

  module_function

  # A automação ligada como a tela liga: a receita passa pela conferência do salvar. A receita que o salvar recusa
  # devolve nil (a lacuna segue aberta), nunca erro.
  def ligada(account, dono, gatilho, passos)
    definicao = FactoryBot.create(:autonomia_automacao, account: account, ligada_por: dono)
    versao = definicao.versoes.create(account: account, numero: 1, receita: { 'gatilho' => gatilho, 'passos' => passos }, autor: dono)
    return unless versao.persisted?

    definicao.update!(versao_ativa: versao, ativa: true)
    definicao
  end

  # A rodada que a Partida enfileirou, um job por vez, como no Sidekiq.
  def rodar_as_rodadas
    fila = ActiveJob::Base.queue_adapter.enqueued_jobs
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = fila.find { |item| item[:job] == Autonomia::Automacao::AvancarJob }
      return unless job

      fila.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end

  WEBHOOK_DA_SONDA = 'https://93.184.216.34/sonda-g13'.freeze

  # G13: a conversa resolvida dispara a automação, o passo "webhook" manda o corpo ao outro sistema (um receptor WebMock
  # num IP público, sem DNS, que grava o pedido) e o histórico registra o envio com o host e o código. Roda na transação
  # do exemplo, que desfaz tudo.
  def webhook_envia_e_registra?
    recebidos = receptor_da_sonda
    account = FactoryBot.create(:account)
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
    dono = FactoryBot.create(:user, account: account, role: :administrator)
    conversa = FactoryBot.create(:conversation, account: account)
    conversa.contact.update!(name: 'Sonda G13')
    passo = { 'id' => 'sonda', 'tipo' => 'webhook', 'descricao' => 'Sonda', 'url' => WEBHOOK_DA_SONDA,
              'corpo' => { 'nome' => { '$valor' => 'contato.nome' } } }
    definicao = ligada(account, dono, { 'tipo' => 'conversa.resolvida' }, [passo])
    return false unless definicao

    Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida').call
    rodar_as_rodadas
    registro = Autonomia::Automacao::Registro.find_by(automacao_id: definicao.id, passo: 'sonda')
    recebidos == [{ 'nome' => 'Sonda G13' }] && registro&.resultado == 'ok' &&
      registro.dados.slice('host', 'codigo') == { 'host' => '93.184.216.34', 'codigo' => 200 }
  ensure
    Current.reset
  end

  # O outro sistema da sonda G13: grava o corpo de cada pedido e responde 200.
  def receptor_da_sonda
    [].tap do |recebidos|
      WebMock::API.stub_request(:post, WEBHOOK_DA_SONDA).to_return do |pedido|
        recebidos << JSON.parse(pedido.body)
        { status: 200, body: { ok: true }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
    end
  end

  # G45: a automação que começa pela mensagem da conversa tem no "Só se" a etapa do card da conversa e a foto ou PDF. O
  # texto não a começa; a foto, com o card na etapa, começa. A receita que o salvar recusa (o card fora do alcance da
  # conversa) é lacuna aberta. Roda na transação do exemplo, que desfaz tudo; a rodada só fica na fila.
  def so_se_da_conversa_le_o_card?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      account = FactoryBot.create(:account)
      account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
      dona = FactoryBot.create(:user, account: account, role: :administrator)
      funil, etapa = create_crm_pipeline(account: account, user: dona)
      conversa = FactoryBot.create(:conversation, account: account)
      account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Sonda G45', currency: 'BRL', primary_conversation: conversa,
                                contact: conversa.contact, inbox: conversa.inbox)
      espera = { 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }
      definicao = ligada(account, dona, filtro_do_card_e_do_anexo(etapa), [espera])
      definicao.present? && [nil, 'sample.png'].map { |arquivo| comecou?(definicao, conversa, arquivo) } == [false, true]
    end
  end

  def filtro_do_card_e_do_anexo(etapa)
    { 'tipo' => 'mensagem.criada', 'filtros' => [{ 'campo' => { '$valor' => 'mensagem.tem_anexo' }, 'op' => 'igual', 'valor' => true },
                                                 { 'campo' => { '$valor' => 'card.etapa_id' }, 'op' => 'igual', 'valor' => etapa.id }] }
  end

  # A mensagem do cliente (só texto, ou a foto `arquivo`) passa pela Partida: a execução abriu?
  def comecou?(definicao, conversa, arquivo)
    mensagem = conversa.messages.new(account: conversa.account, inbox: conversa.inbox, message_type: :incoming, sender: conversa.contact,
                                     content: arquivo ? nil : 'Já mando')
    if arquivo
      anexo = mensagem.attachments.new(account_id: conversa.account_id, file_type: :image)
      anexo.file.attach(io: Rails.root.join('spec/assets', arquivo).open, filename: arquivo, content_type: 'image/png')
    end
    mensagem.save!
    Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'mensagem.criada', mensagem: mensagem).call
    Autonomia::Automacao::Execucao.exists?(automacao_id: definicao.id)
  end
end

# As lacunas do placar (G*, seção 5 do doc), cada uma com a sonda que diz se ela já fechou na main. O exemplo pendente
# confere as sondas das lacunas dele: quando todas fecham, o pendente passa, o RSpec acusa ("Expected pending ... to
# fail") e o exemplo ganha o spec de verdade. A frente que fecha uma lacuna ajusta a sonda no mesmo PR, se o nome que
# ela deu for outro. Sonda `nil` é lacuna sem pergunta que o código responda: a frente troca pela prova.
module FechamentoAutomacao::Lacunas
  extend CrmHelpers

  module_function

  def passo?(*tipos) = tipos.intersect?(tipos_de_passo(Autonomia::Automacao::Receita::ESQUEMA))

  # Os `tipo` fixos (`"tipo": { "const": ... }`) do esquema da receita.
  def tipos_de_passo(trecho)
    case trecho
    when Hash then [trecho.dig('properties', 'tipo', 'const'), *trecho.values.flat_map { |filho| tipos_de_passo(filho) }].compact
    when Array then trecho.flat_map { |filho| tipos_de_passo(filho) }
    else []
    end
  end

  # O campo `campo` existe no passo de tipo `tipo` do esquema da receita.
  def campo_do_passo?(tipo, campo) = campos_do_passo(Autonomia::Automacao::Receita::ESQUEMA, tipo).include?(campo)

  def campos_do_passo(trecho, tipo)
    case trecho
    when Hash
      proprios = trecho.dig('properties', 'tipo', 'const') == tipo ? trecho['properties'].keys : []
      proprios + trecho.values.flat_map { |filho| campos_do_passo(filho, tipo) }
    when Array then trecho.flat_map { |filho| campos_do_passo(filho, tipo) }
    else []
    end
  end

  def gatilho?(*tipos) = tipos.any? { |tipo| Autonomia::Automacao::Gatilhos.entrada(tipo) }
  def gatilho_no?(alvo) = Autonomia::Automacao::Gatilhos::LISTA.values.any? { |entrada| entrada.alvo == alvo }
  def gatilho_de?(origem) = Autonomia::Automacao::Gatilhos::LISTA.values.any? { |entrada| entrada.origem == origem }
  def acao?(acao) = Autonomia::Automacao::AcoesPermitidas.permitida?(acao)
  def valor?(caminho) = Autonomia::Automacao::Valores.caminho_valido?(caminho)

  # G16: o corpo de uma ação aceita valor calculado. O esquema da receita deixa a data calculada no corpo, e o motor a
  # monta na hora: hoje + 6 meses sai como "AAAA-MM-DD", no fuso da conta.
  def valor_calculado_no_corpo?
    data = { '$data' => { 'de' => 'hoje', 'mais' => { 'valor' => 6, 'unidade' => 'meses' } } }
    corpo = { 'merge' => true, 'custom_attributes' => { 'revisao' => data } }
    passo = { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
              'caminho' => { 'id' => { '$valor' => 'conversa.id' } }, 'corpo' => corpo }
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }
    conta = Account.new(custom_attributes: { 'timezone' => 'UTC' })
    montado = Autonomia::Automacao::Corpo.new(corpo, valores: nil, conta: conta).montar
    Autonomia::Automacao::Receita.esquema_valido?(receita) &&
      montado.corpo&.dig('custom_attributes', 'revisao') == Time.current.utc.to_date.advance(months: 6).iso8601
  end

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
  # campo do card do tipo contato (decisão 16).
  def filha_na_maria
    account = FactoryBot.create(:account)
    account.enable_features!('automacao_fundacao', 'automacao_motor')
    FactoryBot.create(:custom_attribute_definition, account: account, attribute_key: 'indicado_por', attribute_display_name: 'Indicado por',
                                                    attribute_model: 'card_attribute', attribute_display_type: 'contato')
    maria = account.contacts.create!(name: 'Maria')
    dona = FactoryBot.create(:user, account: account, role: :administrator)
    mae = mae_com_passo_em_outro(account, card_do_joao(account, dona, maria), dona)
    abrir_filhas(mae) && Autonomia::Automacao::Execucao.find_by(automacao_id: mae.automacao_id, alvo: maria)
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

  # G30: o lead do formulário entra pelo Importer, como no webhook, num funil com a Atribuição ligada e um corretor que
  # cuida dele; o card nasce com esse corretor de dono. Roda na transação do exemplo, que desfaz tudo.
  def lead_ganha_dono_pela_atribuicao?
    account = FactoryBot.create(:account)
    corretor = FactoryBot.create(:user, account: account, role: :agent)
    funil, etapa = create_crm_pipeline(account: account, user: FactoryBot.create(:user, account: account, role: :administrator))
    funil.update!(metadata: { 'ai' => { 'handoff' => { 'enabled' => true, 'prefer_online' => false } } })
    account.crm_pipeline_inboxes.create!(pipeline: funil, inbox: create_crm_whatsapp_api_inbox(account: account, members: [corretor]))
    lead = { 'id' => 'sonda-g30', 'created_time' => '2026-11-08T12:00:00+0000', 'form_id' => '9001',
             'field_data' => [{ 'name' => 'phone_number', 'values' => ['+5511987650030'] }] }
    Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: funil, stage: etapa, form_name: 'Sonda').import(lead)
    Crm::MetaAdsLead.find_by(account: account, leadgen_id: 'sonda-g30')&.card&.owner_id == corretor.id
  end

  SONDAS = {
    # O modelo aprovado entrou como campo do passo "mensagem" (F4b, #2468/#2586), não como passo próprio.
    'G1' => -> { campo_do_passo?('mensagem', 'modelo') },
    'G2' => -> { passo?('email') },
    'G3' => -> { passo?('retorno') },
    # O "criar card" entrou como passo próprio (#2628), não como a ação POST crm/cards.
    'G4' => -> { passo?('card') },
    'G5' => -> { gatilho_no?('Crm::Card') },
    'G6' => -> { gatilho_de?(:tempo) },
    'G7' => -> { gatilho_de?(:recorrente) },
    'G8' => -> { gatilho?('mensagem.falhou') },
    # A troca de dono e a de time do card: a receita do ex. 17 (quem cuidava antes ausente) dispara e lê os nomes.
    'G9' => -> { FechamentoAutomacao::SondasDaTroca.troca_de_responsavel_dispara? && gatilho?('card.time_mudou') },
    'G10' => -> { gatilho?('etiqueta.posta', 'conversa.etiqueta_posta', 'contato.etiqueta_posta') },
    'G11' => -> { valor?('conversa.equipe_respondeu') && valor?('conversa.cliente_respondeu') },
    'G12' => lambda {
      gatilho?('card.reuniao_marcada') && gatilho?('card.reuniao_cancelada') &&
        %w[card.link_da_agenda conversa.link_da_agenda].any? { |caminho| valor?(caminho) }
    },
    # G13 (#2670): o passo manda de verdade e o histórico registra; o ponta a ponta está em
    # spec/fechamento/automacao/g13_webhook_spec.rb.
    'G13' => -> { FechamentoAutomacao::Comportamento.webhook_envia_e_registra? },
    # Fechada com prova (#2630): o passo existe no esquema e o motor o roda; o ponta a ponta está em
    # spec/fechamento/automacao/g14_campanhas_spec.rb.
    'G14' => -> { passo?('campanha') && Autonomia::Automacao::Executor::NATIVOS.key?('campanha') },
    # A Atribuição é o motor único de entrega, inclusive para agente de IA (regra do Rodrigo). A F7 fechou por outro
    # caminho (G15, D1): o passo próprio "ia_assumir", que passa pela Atribuição do CRM, e não `assignee_type` no
    # atribuir, que a lista agora proíbe. "Tirar" é atribuir de volta à pessoa ou ao time, que o passo já faz.
    'G15' => -> { passo?('ia_assumir') },
    'G16' => -> { valor_calculado_no_corpo? },
    'G17' => -> { acao?('POST contacts') },
    'G18' => -> { filha_anda_no_registro_ligado? },
    'G19' => -> { acao?('POST contacts/:contact_id/notes') },
    # Os passos de IA leem a foto, o PDF e o áudio da conversa (`le: anexos`, #2669).
    'G20' => -> { Autonomia::Automacao::Receita::ESQUEMA.dig('definitions', 'leituras', 'items', 'enum').include?('anexos') },
    # Fechada com prova (#2706): o passo roda e cria o card; o ponta a ponta do exemplo 9 está em
    # spec/fechamento/automacao/exemplo_09_prospeccao_semanal_spec.rb.
    'G21' => -> { FechamentoAutomacao::SondasDoExemplo9.prospeccao_cria_o_card? },
    # G22 (exemplo 8, passo 9): desligada nesta entrega (Solicitados::GRAVADORES vazio). Liga quando o "para cada item"
    # (G24) gravar o solicitante no card; aí a sonda volta a ser SondasDoExemplo8.rh_avisado_do_que_falta?.
    'G22' => nil,
    # G23 (#2737): o "ausente até" de quem cuida, como valor da condição.
    'G23' => -> { valor?('card.responsavel_ausente') && valor?('conversa.responsavel_ausente') },
    # Fechada com prova (#2771): o "para cada item" abre um card por item, cada um numa raiz própria da cadeia, e a
    # automação de card criado roda em todos (spec/services/autonomia/automacao/para_cada_cadeia_spec.rb; exemplo 8,
    # passos 1 a 5, em spec/fechamento/automacao/exemplo_08_funcionario_novo_spec.rb).
    'G24' => -> { FechamentoAutomacao::SondasDoExemplo8.segunda_automacao_em_cada_card? },
    'G25' => -> { acao?('POST crm/cards/:id/close') },
    'G26' => -> { passo?('sla') },
    # "Card criado ou atualizado com valor acima de R$ 50 mil" (15) e "card completo" (8, passo 8): só o card criado é a G5.
    'G27' => -> { gatilho?('card.atualizado', 'card.campo_mudou', 'card.valor_mudou') },
    # O texto da IA vira valor entre passos (`ia.<passo>`, #2679): fora da janela, a "mensagem" o leva no modelo aprovado
    # (exemplo 3, passo 2); o "mesmo resumo" não vai outra vez à IA (exemplo 10, passo 6).
    'G28' => -> { valor?('ia.cuidados') },
    # Achadas no exemplo 2 (07/11). As ainda sem desenho ficam nil: a frente dona troca pela sonda quando escolher o caminho.
    # G29 (#2702): de onde o card veio e o anúncio do formulário, valores da receita. Ponta a ponta em
    # spec/fechamento/automacao/g29_origem_do_card_spec.rb.
    'G29' => -> { valor?('card.origem') && valor?('card.anuncio') },
    # G30 (#2702): o card do lead nasce com o dono que a Atribuição do funil daria (o corretor), para o retorno e o link
    # da agenda. Ponta a ponta em spec/fechamento/automacao/g30_dono_do_lead_spec.rb.
    'G30' => -> { lead_ganha_dono_pela_atribuicao? },
    # G31: voltar a esperar e decidir de novo a cada resposta, enquanto a IA diz "ainda conversando" (o `de_novo` do
    # decidir); prova ponta a ponta em spec/fechamento/automacao/g31_decidir_a_cada_resposta_spec.rb.
    'G31' => -> { campo_do_passo?('decidir', 'de_novo') },
    # G32 (#2703): a reunião marcada como condição do "esperar até", no meio da execução; prova ponta a ponta em
    # spec/fechamento/automacao/g32_reuniao_spec.rb.
    'G32' => -> { valor?('card.tem_reuniao_marcada') },
    # #2680: a receita escolhe a caixa por onde abrir a conversa de quem não tem uma (o lead do formulário, o contato).
    'G33' => -> { Autonomia::Automacao::Receita::ESQUEMA.dig('properties', 'gatilho', 'properties').key?('conversa_nova') },
    # #2680: a resposta em outra conversa do contato conta, e a mensagem que a automação mandou vira valor.
    'G34' => -> { valor?('envio.texto') && valor?('envio.situacao') },
    # A IA lê o card (`le: card`, #2679): exemplo 13, passo 5; exemplo 15, passo 9.
    'G35' => -> { Autonomia::Automacao::Receita::ESQUEMA.dig('definitions', 'leituras', 'items', 'enum').include?('card') },
    # A IA lê as notas internas da conversa (`le: notas`, #2679): exemplo 5, passo 1.
    'G36' => -> { Autonomia::Automacao::Receita::ESQUEMA.dig('definitions', 'leituras', 'items', 'enum').include?('notas') },
    # Achadas no exemplo 7 (auditoria dos termos, 07/11); G33 e G34 são do lote 3 (#2680), G35 e G36 da F7 (#2688).
    # O lote 5 (#2686) traz as peças da G37 e da G38, com as sondas prontas em FechamentoAutomacao::SondasDaCampanha
    # (spec/support/fechamento_automacao_campanha.rb). Elas ficam desligadas até o PR do spec de ponta a ponta do
    # exemplo 7, que as liga; até lá o exemplo 7 segue em pendentes_spec.
    # G37: o público da campanha com exclusão ("todos os outros", "perguntou e não comprou").
    # Sonda: FechamentoAutomacao::SondasDaCampanha.campanha_para_todos_os_outros?
    'G37' => nil,
    # G38: o filtro "respondeu à campanha X" no gatilho da mensagem.
    # Sonda: FechamentoAutomacao::SondasDaCampanha.filtro_da_campanha_filtra?
    'G38' => nil,
    # G39 (#2753): o gatilho que roda uma vez, numa data ("a quinta antes da Black Friday"), não toda semana.
    'G39' => lambda {
      gatilho = { 'tipo' => 'conta.recorrente', 'frequencia' => 'uma_vez', 'data' => '2030-11-28', 'hora' => 9 }
      passo = { 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }
      Autonomia::Automacao::Receita.esquema_valido?({ 'gatilho' => gatilho, 'passos' => [passo] })
    },
    # Do exemplo 10 (#2678), fora do lote 2: esperar só a pessoa que atende a conversa (a Fernanda), não a equipe inteira.
    'G40' => -> { valor?('conversa.responsavel_respondeu') },
    # Do exemplo 10 (#2678, #2752): a instrução no resumir ("o que já foi prometido") e avisar o responsável quando a
    # agente de IA atende a conversa (o dono do card; sem ele, o passo pula com sem_responsavel).
    'G41' => -> { campo_do_passo?('resumir', 'instrucao') && I18n.exists?('autonomia.automacao.motivos.sem_responsavel', :pt_BR) },
    # Da auditoria dos termos (07/11, #2716): a automação que começa pela conversa lê o card dela no "Só se" (exemplo 14,
    # passo 2) e o filtro sabe se a mensagem tem anexo (exemplo 18, começo).
    'G45' => -> { FechamentoAutomacao::Comportamento.so_se_da_conversa_le_o_card? },
    # Do exemplo 4 (#2650): a etiqueta como contador de faltas. Com a execução da primeira falta esperando os 30 dias, a
    # nova entrada em "Faltou" no mesmo card não abre outra (Partida, `ja_aberta`): o contador nunca chega a 2.
    'G50' => nil,
    # Do exemplo 20, passo 9 (termo à risca: "coloca o cliente na campanha de e-mail"): pôr o contato numa campanha de
    # e-mail. A G14 cobre só WhatsApp; etiqueta + G7 + G2 é adaptar, não conta.
    'G52' => nil,
    # Do exemplo 1, passo 12 (#2721, #2763): o resumo lê tudo o que a execução tentou, até o e-mail em conversa própria.
    'G42' => -> { Autonomia::Automacao::EnviosDaExecucao.method_defined?(:dados) },
    # G43 (#2700): a mensagem vai ao número novo do contato depois que a automação o atualiza (ex. 19, passos 4 e 7),
    # só quando o número da conversa morreu (a última mensagem da empresa nela falhou).
    'G43' => -> { FechamentoAutomacao::SondasDoExemplo19.mensagem_vai_ao_numero_novo? },
    # G48 (do exemplo 12, passo 3): o campo do card preenchido acorda o "esperar até" na hora, pelo gancho único do card
    # (Crm::CardAvisaAutomacao, lote 4, #2682); prova ponta a ponta em spec/fechamento/automacao/g48_campo_do_card_spec.rb.
    'G48' => -> { FechamentoAutomacao::SondasDoExemplo12.campo_do_card_acorda_a_espera? },
    # G49 (ex. 11, passo 3; ex. 6, passos 5 e 6): o registro que um passo criou vira valor (`criado.<passo>`) e alvo dos
    # passos seguintes: o card nasce no contato criado e o "em outro registro" roda no registro criado. Prova ponta a
    # ponta em spec/fechamento/automacao/exemplo_11_indicacao_spec.rb.
    'G49' => lambda {
      valor?('criado.p1') && campo_do_passo?('card', 'contato') &&
        Autonomia::Automacao::Receita::ESQUEMA.dig('definitions', 'registro_ligado', 'oneOf').any? do |forma|
          forma.dig('properties', 'de', 'const') == 'criado_no_passo'
        end
    },
    # G65 (#2842, ex. 11, passo 7): a filha lê o registro de origem (o João, no card ganho) com `origem.*`.
    'G65' => -> { filha_le_a_origem? },
    # Achada no #2675 (09/11), ainda sem desenho: a frente dona troca o nil pela sonda quando escolher o caminho.
    # G55 (ex. 16, passo 2): disparar a campanha da etiqueta a partir de um gatilho de card. A campanha só sai do
    # conta.recorrente (`campanha_so_sem_alvo`), e o "para cada card perdido" é o card.recorrente.
    'G55' => nil,
    # Do exemplo 19, também da Gatilhos (#2637, 08/11). G53: o conteúdo da mensagem que falhou como valor da receita
    # (passo 2, "manda por e-mail o mesmo conteúdo"): `falhou.texto`, prova em g53_conteudo_da_falha_spec.rb.
    'G53' => -> { valor?('falhou.texto') },
    # G54: esperar a entrega da mensagem (passo 5, "Chegou: tira a etiqueta e grava uma nota"); fechada pela G34.
    'G54' => -> { valor?('envio.situacao') },
    # Do exemplo 17, achadas na G9 (#2707). G62 (#2829): o campo do card do tipo pessoa da equipe, com o nome e a
    # ausência dela (passos 3, 5 e 6). G63 (#2830): o galho "a cada mensagem do cliente" do "esperar até" (passo 4).
    # G64 (#2839): a conferência toda manhã, numa hora marcada, na mesma automação (passo 5). Prova ponta a ponta em
    # spec/fechamento/automacao/exemplo_17_ferias_spec.rb. G66 (#2843, decisão 14): o passo "passar a conversa para o
    # responsável do card" leva a conversa da antiga dona à nova, e "espera a Renata responder" (passo 4) lê a Renata.
    # G67 (#2844): o resumo da volta (passo 6) lê as mensagens desde o começo da execução (as férias), com teto.
    'G62' => -> { FechamentoAutomacao::SondasDaTroca.campo_pessoa_le_na_conta? },
    'G63' => -> { FechamentoAutomacao::SondasDoExemplo17.galho_a_cada_mensagem? },
    'G64' => -> { FechamentoAutomacao::SondasDoExemplo17.conferencia_marcada? },
    # Com a decisão 18, corrigida: a agente de IA cobre a Renata (opção do passo) e, quando ela escreve, a conversa volta
    # sozinha para ela.
    'G66' => lambda {
      FechamentoAutomacao::SondasDoExemplo17.conversa_acompanha_o_responsavel? && FechamentoAutomacao::SondasDoExemplo17.ia_assume_e_devolve?
    },
    'G67' => -> { FechamentoAutomacao::SondasDoExemplo17.resumo_le_o_periodo? },
    # Do exemplo 19, passo 3 (#2864): o extrair lê só a conversa da execução; a resposta do e-mail fica fora. Aberta.
    'G68' => nil,
    # Do exemplo 14, passo 5 (#2791): o laço dos documentos numa automação só. O "esperar até" lê o documento novo, e o
    # "decidir" volta a ele (`de_novo.desde`). Prova em spec/fechamento/automacao/exemplo_14_documentacao_spec.rb.
    'G46' => lambda {
      opcoes = Autonomia::Automacao::Receita::ESQUEMA.dig('definitions', 'de_novo', 'oneOf')
      valor?('conversa.cliente_mandou_documento') && Array(opcoes).any? { |opcao| opcao.dig('properties', 'desde') }
    },
    # Do exemplo 20, passos 5 e 8 (#2756): o link da agenda de uma página escolhida na receita, não só o do responsável.
    'G44' => -> { FechamentoAutomacao::SondasDaAgenda.link_da_pagina_escolhida? },
    # Do exemplo 5, passo 8 (#2755): o card em que a página põe a reunião ganha a conversa do contato no WhatsApp dos
    # avisos da página; prova ponta a ponta no passo 8 de spec/fechamento/automacao/exemplo_05_revisao_do_carro_spec.rb.
    'G47' => -> { FechamentoAutomacao::SondasDaAgenda.card_da_pagina_ganha_a_conversa? },
    # Do exemplo 6, passo 8 (G56): o gatilho "reunião atendida", o primeiro "Aconteceu" da reunião na Agenda; prova ponta
    # a ponta em spec/fechamento/automacao/g56_reuniao_atendida_spec.rb.
    'G56' => -> { gatilho?('card.reuniao_atendida') },
    # Do exemplo 6, passo 8, numa automação só (G59): esperar a reunião do contato acontecer, no meio da execução, e o
    # resultado da reunião acordar essa espera; prova em spec/fechamento/automacao/g59_reuniao_atendida_na_espera_spec.rb.
    'G59' => lambda {
      valor?('contato.reuniao_atendida') && Autonomia::Automacao::EsperaDaReuniao::VALORES.include?('contato.reuniao_atendida')
    },
    # Do exemplo 6, passo 2 (G60): o link da agenda numa automação que roda no contato, pela ponte da conversa nova
    # (#2680) até a conversa dele na caixa escolhida; prova no mesmo spec da G59. A sonda passa pelo salvar
    # (Receita#problemas): a receita com a página de reserva da conta no gatilho sai sem problema.
    'G60' => -> { valor?('conversa.link_da_agenda') && FechamentoAutomacao::SondasDaAgenda.reserva_no_gatilho_salva? },
    # Do exemplo 6, passo 6 (G61): avisar quem atende a reunião fora dos gatilhos de reunião (a próxima marcada do contato,
    # em card que quem ligou vê); prova no mesmo spec da G59. A sonda passa pelo salvar (Receita#problemas): o "quem atende
    # a reunião" num gatilho de conversa sai sem problema (antes da G61, recusava com da_reuniao_so_no_gatilho).
    'G61' => -> { FechamentoAutomacao::SondasDaAgenda.da_reuniao_em_qualquer_gatilho_salva? },
    # Do exemplo 9, passo 4 (#2779): a campanha vai só a quem os passos anteriores desta execução criaram
    # (`publico: desta_execucao`), não a todo contato com a etiqueta do mês. Prova em g58_publico_da_execucao_spec.rb.
    'G58' => -> { FechamentoAutomacao::SondasDoExemplo9.publico_so_dos_criados? },
    # G57 (#2769, ex. 1, passo 7): o retorno "para hoje" (ou amanhã), numa hora ou no fim do dia, no fuso da conta.
    'G57' => -> { FechamentoAutomacao::SondasDoExemplo1.hora_de_hoje_que_passou_vence_agora? }
  }.freeze

  # O que fazer quando o pendente passa e o RSpec acusa "Expected pending … to fail".
  SE_PASSOU = 'Se este pendente passou, as lacunas do exemplo %s fecharam: mova-o para o arquivo próprio em ' \
              'spec/fechamento/automacao/ com o spec de ponta a ponta, ou avise a sessão do fechamento (#2570).'.freeze

  # As lacunas da lista que ainda estão abertas.
  def abertas(codigos) = codigos.reject { |codigo| SONDAS.fetch(codigo)&.call }
end

RSpec.configure do |config|
  config.include FechamentoAutomacao, :fechamento_automacao
end
