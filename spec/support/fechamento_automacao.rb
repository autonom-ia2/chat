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

# As lacunas do placar (G*, seção 5 do doc), cada uma com a sonda que diz se ela já fechou na main. O exemplo pendente
# confere as sondas das lacunas dele: quando todas fecham, o pendente passa, o RSpec acusa ("Expected pending ... to
# fail") e o exemplo ganha o spec de verdade. A frente que fecha uma lacuna ajusta a sonda no mesmo PR, se o nome que
# ela deu for outro. Sonda `nil` é lacuna sem pergunta que o código responda: a frente troca pela prova.
module FechamentoAutomacao::Lacunas
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
    'G9' => -> { gatilho?('card.responsavel_mudou', 'conversa.responsavel_mudou') },
    'G10' => -> { gatilho?('etiqueta.posta', 'conversa.etiqueta_posta', 'contato.etiqueta_posta') },
    'G11' => -> { valor?('conversa.equipe_respondeu') && valor?('conversa.cliente_respondeu') },
    'G12' => lambda {
      gatilho?('card.reuniao_marcada') && gatilho?('card.reuniao_cancelada') &&
        %w[card.link_da_agenda conversa.link_da_agenda].any? { |caminho| valor?(caminho) }
    },
    'G13' => -> { passo?('webhook') },
    # Fechada com prova (#2630): o passo existe no esquema e o motor o roda; o ponta a ponta está em
    # spec/fechamento/automacao/g14_campanhas_spec.rb.
    'G14' => -> { passo?('campanha') && Autonomia::Automacao::Executor::NATIVOS.key?('campanha') },
    # A Atribuição é o motor único de entrega, inclusive para agente de IA (regra do Rodrigo). A F7 fechou por outro
    # caminho (G15, D1): o passo próprio "ia_assumir", que passa pela Atribuição do CRM, e não `assignee_type` no
    # atribuir, que a lista agora proíbe. "Tirar" é atribuir de volta à pessoa ou ao time, que o passo já faz.
    'G15' => -> { passo?('ia_assumir') },
    'G16' => -> { valor_calculado_no_corpo? },
    'G17' => -> { acao?('POST contacts') },
    'G18' => -> { passo?('em_outro_registro') },
    'G19' => -> { acao?('POST contacts/:contact_id/notes') },
    # Os passos de IA leem a foto, o PDF e o áudio da conversa (`le: anexos`, #2669).
    'G20' => -> { Autonomia::Automacao::Receita::ESQUEMA.dig('definitions', 'leituras', 'items', 'enum').include?('anexos') },
    'G21' => -> { passo?('prospeccao') },
    'G22' => nil,
    # G23 (#2737): o "ausente até" de quem cuida, como valor da condição.
    'G23' => -> { valor?('card.responsavel_ausente') && valor?('conversa.responsavel_ausente') },
    'G24' => nil,
    'G25' => -> { acao?('POST crm/cards/:id/close') },
    'G26' => -> { passo?('sla') },
    # "Card criado ou atualizado com valor acima de R$ 50 mil" (15) e "card completo" (8, passo 8): só o card criado é a G5.
    'G27' => -> { gatilho?('card.atualizado', 'card.campo_mudou', 'card.valor_mudou') },
    # O texto da IA vira valor entre passos (`ia.<passo>`, #2679): fora da janela, a "mensagem" o leva no modelo aprovado
    # (exemplo 3, passo 2); o "mesmo resumo" não vai outra vez à IA (exemplo 10, passo 6).
    'G28' => -> { valor?('ia.cuidados') },
    # Achadas no exemplo 2 (07/11), ainda sem desenho: a frente dona troca o nil pela sonda quando escolher o caminho.
    # G29: a origem do card do formulário (anúncio, formulário) como valor da receita, no filtro do gatilho e nos passos.
    'G29' => nil,
    # G30: o responsável por um anúncio (o corretor daquele anúncio), para o retorno e o link da agenda.
    'G30' => nil,
    # G31: voltar a esperar e decidir de novo a cada resposta, enquanto a IA diz "ainda conversando".
    'G31' => nil,
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
    # Fecham com o lote 5 (#2686: a exclusão e o "respondeu à campanha") e com o PR do exemplo 7 da G14 (#2681, parte 4:
    # a data única); a G14 liga as sondas e o spec do exemplo 7 no PR dela.
    # G37: o público da campanha com exclusão ("todos os outros", "perguntou e não comprou").
    'G37' => nil,
    # G38: o filtro "respondeu à campanha X" no gatilho da mensagem.
    'G38' => nil,
    # G39: o gatilho que roda uma vez, numa data ("a quinta antes da Black Friday"), não toda semana.
    'G39' => nil,
    # Do exemplo 10 (#2678), fora do lote 2: esperar só a pessoa que atende a conversa (a Fernanda), não a equipe inteira.
    'G40' => -> { valor?('conversa.responsavel_respondeu') },
    # Do exemplo 10 (#2678, #2752): a instrução no resumir ("o que já foi prometido") e avisar o responsável quando a
    # agente de IA atende a conversa (o dono do card; sem ele, o passo pula com sem_responsavel).
    'G41' => -> { campo_do_passo?('resumir', 'instrucao') && I18n.exists?('autonomia.automacao.motivos.sem_responsavel', :pt_BR) },
    # Do exemplo 1, passo 12 (#2721, #2763): o resumo lê tudo o que a execução tentou, até o e-mail em conversa própria.
    'G42' => -> { Autonomia::Automacao::EnviosDaExecucao.method_defined?(:dados) },
    # G43 (#2700): a mensagem vai ao número novo do contato depois que a automação o atualiza (ex. 19, passos 4 e 7). Fica
    # com a Gatilhos, depois do lote 3 (#2689), que traz a porta da frente da conversa nova.
    'G43' => nil,
    # G49 (ex. 11, passo 3; ex. 6, passos 5 e 6): o registro que um passo criou vira valor (`criado.<passo>`) e alvo dos
    # passos seguintes: o card nasce no contato criado e o "em outro registro" roda no registro criado. Prova ponta a
    # ponta em spec/fechamento/automacao/exemplo_11_indicacao_spec.rb.
    'G49' => lambda {
      valor?('criado.p1') && campo_do_passo?('card', 'contato') &&
        Autonomia::Automacao::Receita::ESQUEMA.dig('definitions', 'registro_ligado', 'oneOf').any? do |forma|
          forma.dig('properties', 'de', 'const') == 'criado_no_passo'
        end
    },
    # Achada no #2675 (09/11), ainda sem desenho: a frente dona troca o nil pela sonda quando escolher o caminho.
    # G55 (ex. 16, passo 2): disparar a campanha da etiqueta a partir de um gatilho de card. A campanha só sai do
    # conta.recorrente (`campanha_so_sem_alvo`), e o "para cada card perdido" é o card.recorrente.
    'G55' => nil,
    # Do exemplo 19, também da Gatilhos (#2637, 08/11). G53: o conteúdo da mensagem que falhou como valor da receita
    # (passo 2, "manda por e-mail o mesmo conteúdo").
    'G53' => nil,
    # G54: esperar a entrega da mensagem (passo 5, "Chegou: tira a etiqueta e grava uma nota"); fechada pela G34.
    'G54' => -> { valor?('envio.situacao') },
    # Do exemplo 5, passo 8 (#2703): o card que a página de agendamento cria para a reunião (card do serviço já ganho)
    # nasce sem conversa, e a mensagem do gatilho de reunião nele pula com `sem_conversa`. Caminho escolhido: o Booker
    # liga ao card novo a conversa do contato na caixa da página, quando ela existe. A frente dona troca o nil pela sonda.
    'G47' => nil
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
