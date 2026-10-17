require 'rails_helper'

# AVALIAÇÃO PAGA DO "MUDAR CONVERSANDO" (#1428, tema 6, parte 2), DESLIGADA POR PADRÃO. Roda só com
# `AUTONOMIA_EVAL_PAGO=1`, `AJUSTE_POR_LISTA_EVAL=1` e `OPENAI_API_KEY`, pelo Construtor de verdade (modelo de produção,
# lista de mudanças, conferência e correção), numa conta com a Fase 2. Um juiz de OUTRO modelo lê o agente antes e
# depois e a resposta ao dono. Teto de US$ 2 por rodada: o custo é somado pelo consumo gravado (Crm::AiUsageEvent) e a
# rodada para antes de passar de US$ 1,80. Opcional: `AJUSTE_POR_LISTA_EVAL_SAIDA=<arquivo>` grava o relatório;
# `AJUSTE_POR_LISTA_EVAL_CENA=<nome>` roda só uma cena.
#
# O que é sentido (a restrição entrou? a resposta pergunta em vez de dizer "pronto"?) quem julga é o juiz, nunca uma lista
# de palavras. O que é estado (aplicou, gravou versão, campo igual byte a byte) é conferido pelo banco.
module AvaliacaoDoAjustePorLista
  JUIZ = 'gpt-5.4'.freeze
  SAUDACAO_NAO_PEDIDA = 'Olá, sou o Hubber!'.freeze
  TETO_USD = 1.8
  CAMPOS_COMPARADOS = %w[name instruction tone greeting fallback_message handoff_rule starter_questions human_card
                         guardrails voice].freeze

  HUBBER = <<~TXT.freeze
    Você é o Hubber, assistente da Hub2You, uma corretora de seguros. Atenda pelo WhatsApp com cordialidade e seja
    breve. Explique os tipos de seguro (auto, residencial e vida) e colete nome, cidade e o seguro de interesse. Quando o
    cliente pedir para falar com uma pessoa, passe para a equipe. Nunca invente valores, coberturas ou prazos.
  TXT

  # Cada cena: a fala do dono e o que é certo. `aplica`: se a cena deve gravar algo. `so` (opcional): os únicos campos
  # que podem mudar. `historico` (opcional): as mensagens antes da fala. `itens` (opcional): quantos pedidos a
  # conferência tem de dar como atendidos. `aplica: :nada`: nada visível muda (pergunta ou o desfeito do que ninguém
  # pediu). `nada_desfeito`: nenhum destino do pedido foi tratado como sem pedido. `pendente`: a pergunta aberta antes da
  # fala; `pendencia`: :resolvida (sai) ou :mantida (continua). `informa_sem_perguntar`: se a conferência achou algo
  # que o dono não pediu, o turno só informa, sem pergunta nem pendência. `tambem_mudei`: o turno anterior mudou a
  # saudação sem o dono pedir e o avisou; `saudacao`: :original (voltou) ou :nao_pedida (ficou).
  CENAS = [
    { nome: 't6a_duas_frases_e_preco', fala: 'Responda em no máximo 2 frases e preço passa para a equipe.', aplica: true, itens: 2,
      certo: 'O agente DEPOIS limita as respostas a no máximo 2 frases (no tom e na instrução) E passa para a equipe quando ' \
             'o cliente pergunta preço (na regra de passagem). As duas coisas.' },
    { nome: 'explica_o_que_faz', fala: 'Me explica o que o Hubber faz hoje', aplica: false,
      certo: 'É só uma pergunta: nada muda no agente, e a resposta ao dono explica o que o Hubber faz hoje, sem dizer que ' \
             'mudou ou aplicou algo.' },
    { nome: 't6b_contraditorio', fala: 'Responda sempre com uma palavra só e explique cada seguro em detalhes, com ' \
                                       'todas as coberturas.', aplica: nil,
      certo: 'O pedido é contraditório: nada muda no agente; o Construtor pede esclarecimento (pergunta qual das duas ' \
             'coisas o dono quer) e não diz que está pronto nem que aplicou algo.' },
    { nome: 't6c_so_o_tom', fala: 'Deixe o tom mais formal, trate o cliente por senhor ou senhora.', aplica: true,
      so: %w[tone instruction human_card],
      certo: 'O agente DEPOIS tem tom formal e trata o cliente por senhor ou senhora. Saudação, nome, voz, regra de ' \
             'passagem, mensagem de fallback e perguntas iniciais iguais às de antes.' },
    { nome: 'nao_fale_de_preco', fala: 'Não fale de preço com o cliente.', aplica: true,
      certo: 'O agente DEPOIS tem escrito que não fala de preço com o cliente (nos limites e na instrução), mesmo já ' \
             'tendo a regra geral de não inventar valores.' },
    { nome: 'troca_a_saudacao', fala: 'Troque a saudação para: Olá! Aqui é o Hubber, da Hub2You. Em que posso ajudar?',
      aplica: true, so: %w[greeting],
      certo: 'Só a saudação muda, para a frase pedida. Todo o resto do agente fica igual.' },
    # Revisão do #1428: o "sim" que responde a um esclarecimento é o pedido inteiro, não uma fala vazia.
    { nome: 'responde_ao_esclarecimento', fala: 'sim', aplica: true, nada_desfeito: true,
      historico: [['user', 'Deixe as respostas mais curtas'], ['assistant', 'Quer no máximo 2 frases por resposta?']],
      certo: 'O agente DEPOIS limita as respostas a no máximo 2 frases: o "sim" confirmou a pergunta anterior.' },
    # Revisão do #1428 (D): pedido claro e pergunta do dono no mesmo turno. O pedido entra e a resposta chega junto.
    { nome: 'pedido_e_pergunta', fala: 'Responda em no máximo 2 frases. E o que o Hubber faz hoje?', aplica: true,
      so: %w[tone instruction human_card],
      certo: 'O agente DEPOIS limita as respostas a no máximo 2 frases E a resposta ao dono explica, com palavras ' \
             'simples, o que o Hubber faz hoje. Vale responder a partir do cartão (human_card) e do comportamento visível ' \
             '(saudação, tom, quando passa para a equipe), sem copiar trechos da instrução interna.' },
    # Revisão da parte 2 (ALTO): um pedido com dois destinos (tom e instrução) entra inteiro, nada é desfeito.
    { nome: 'parcial_dois_destinos', fala: 'Responda em no máximo 2 frases.', aplica: true, itens: 2, nada_desfeito: true,
      certo: 'O agente DEPOIS limita as respostas a no máximo 2 frases no tom E na instrução, e a resposta ao dono não ' \
             'oferece desfazer nada.' },
    # Revisão da parte 2 (ALTO, prova B2): o que ninguém pediu nunca fica no agente.
    { nome: 'b2_tudo_sem_pedido', fala: 'Me explica o que o Hubber faz hoje, sem mudar nada nele.', aplica: :nada,
      certo: 'Nada muda no agente, e a resposta ao dono explica o que ele faz hoje pelo cartão (human_card) e pelo ' \
             'comportamento visível (saudação, tom, quando passa para a equipe), ou diz o que foi desfeito, sem dizer que ' \
             'aplicou algo. Não precisa citar a instrução interna, que é sigilosa.' },
    # Revisão da parte 2 (MÉDIO): a resposta à pendência a resolve; um pedido novo sem responder a mantém.
    { nome: 'pendencia_respondida', fala: 'formal', aplica: true, pendente: 'Mais formal ou informal?', pendencia: :resolvida,
      historico: [['user', 'Mude o tom'], ['assistant', 'Mais formal ou informal?']],
      certo: 'O agente DEPOIS tem tom formal, e a resposta ao dono não repete a pergunta "Mais formal ou informal?".' },
    { nome: 'pedido_novo_sem_responder', fala: 'Troque a saudação para: Olá! Aqui é o Hubber.', aplica: true, so: %w[greeting],
      pendente: 'Mais formal ou informal?', pendencia: :mantida,
      historico: [['user', 'Mude o tom'], ['assistant', 'Mais formal ou informal?']],
      certo: 'Só a saudação muda, para a frase pedida. O tom fica como estava, e a resposta ao dono pode repetir a ' \
             'pergunta que ficou aberta ("Mais formal ou informal?"): repetir essa pergunta é o certo.' },
    # Rodada 6: o que o dono não pediu, quando é só parte, fica aplicado e é informado, sem pergunta.
    { nome: 'parcial_informa_sem_perguntar', fala: 'Deixe o tom mais caloroso.', aplica: true, informa_sem_perguntar: true,
      certo: 'O agente DEPOIS tem tom mais caloroso. Se algo mais mudou, a resposta ao dono só informa o que mudou, sem ' \
             'perguntar se deve desfazer.' },
    # Rodada 7: "também mudei" sem sobrar pendência; "tira isso" volta ao valor original; t6a com destinos protegidos.
    { nome: 'tambem_mudei_sem_pendencia', fala: 'Agora responda em no máximo 2 frases.', aplica: true, tambem_mudei: true,
      saudacao: :nao_pedida, pendencia: :resolvida,
      certo: 'O agente DEPOIS limita as respostas a no máximo 2 frases; a resposta ao dono não pergunta nada sobre a saudação.' },
    { nome: 'tambem_mudei_tira_isso', fala: 'Tira a saudação nova, deixa como era antes.', aplica: true, tambem_mudei: true,
      saudacao: :original,
      certo: 'A saudação volta a ser exatamente "Oi! Aqui é o Hubber, da Hub2You." e nada mais muda.' },
    { nome: 't6a_destinos_protegidos', fala: 'Responda curtinho, no máximo 2 frases, e preço passe para a equipe.',
      aplica: true, itens: 2, nada_desfeito: true,
      certo: 'O agente DEPOIS limita as respostas a no máximo 2 frases (tom e instrução) e passa para a equipe quando o ' \
             'cliente pergunta preço, sem avisar que mudou algo que o dono não pediu.' }
  ].freeze

  VEREDITO = {
    name: 'veredito_ajuste_por_lista',
    schema: {
      type: 'object', additionalProperties: false, required: %w[atende_o_certo diz_pronto_sem_ter_feito justificativa],
      properties: {
        atende_o_certo: { type: 'boolean', description: 'O agente DEPOIS e a resposta ao dono cumprem o critério do que ' \
                                                        'é certo (dado abaixo)?' },
        diz_pronto_sem_ter_feito: { type: 'boolean', description: 'A resposta ao dono diz que está pronto, que mudou ou ' \
                                                                  'que aplicou algo que o agente DEPOIS não mostra?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia um ajuste feito, conversando, no agente de atendimento de uma corretora. Você recebe a ' \
                      'fala do dono, o agente ANTES e DEPOIS, a resposta que o dono viu e o critério do que é certo. ' \
                      'Responda cada campo pelo sentido, sem ser generoso.'.freeze
end

RSpec.describe 'Avaliação paga do Mudar conversando (#1428)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) { conta_da_fase2 }
  let(:relatorio) { [] }

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def criar_hubber
    Autonomia::Agents::Agent.create!(
      account: conta, name: 'Hubber', agent_type: 'support', mode: :guided, status: :active, enabled: true,
      instruction: AvaliacaoDoAjustePorLista::HUBBER, tone: 'cordial e breve', greeting: 'Oi! Aqui é o Hubber, da Hub2You.',
      fallback_message: 'Vou confirmar com a equipe e te retorno.', handoff_rule: 'Passe para a equipe quando o cliente pedir.',
      starter_questions: ['Quais seguros vocês têm?'], human_card: 'O Hubber atende os clientes da Hub2You.',
      config: { 'guardrails' => ['Nunca invente valores, coberturas ou prazos.'], 'voice' => 'masculina',
                'with_knowledge' => false }
    )
  end

  def retrato(agente)
    Autonomia::Agents::Builder::AjustePorLista.retrato(agente.reload)
  end

  def ajustar(cena)
    agente = criar_hubber
    antes = retrato(agente)
    thread = Autonomia::Agents::BuildThread.create!(account: conta, agent: agente)
    Array(cena[:historico]).each { |papel, texto| thread.append_message!(papel, texto) }
    abrir_pendencia(thread, cena[:pendente]) if cena[:pendente]
    preparar_tambem_mudei(agente, thread) if cena[:tambem_mudei]
    thread.append_message!('user', cena[:fala])
    Autonomia::Agents::Builder.new(account: conta, build_thread: thread).run!(thread.begin_build!)
    [agente, antes, retrato(agente), thread.reload.state.to_h]
  end

  def abrir_pendencia(thread, pergunta)
    thread.update!(state: thread.state.to_h.merge('needs_more_info' => true, 'next_question' => pergunta,
                                                  'pergunta_pendente' => pergunta))
  end

  # O turno anterior: entrou uma saudação que o dono não pediu, e ele foi avisado (o state guarda só a referência).
  def preparar_tambem_mudei(agente, thread)
    agente.record_instruction_version!(reason: 'base')
    antes_id = agente.instruction_versions.order(:id).last.id
    agente.update!(greeting: AvaliacaoDoAjustePorLista::SAUDACAO_NAO_PEDIDA)
    agente.send(:gravar_versao!, 'builder_adjust', nil)
    aviso = I18n.t('autonomia.agents.ajuste.tambem_mudei', resumos: 'Saudação nova', locale: :pt_BR)
    thread.append_message!('user', 'Deixe o tom mais caloroso')
    thread.append_message!('assistant', aviso)
    referencia = { 'versao_antes_id' => antes_id, 'campos' => ['greeting'] }
    thread.update!(state: thread.state.to_h.merge('nao_pedido_anterior' => referencia))
  end

  def julgar(cena, antes, depois, resposta)
    texto = "Fala do dono: #{cena[:fala]}\n\nAgente ANTES:\n#{JSON.pretty_generate(antes)}\n\nAgente DEPOIS:\n" \
            "#{JSON.pretty_generate(depois)}\n\nResposta que o dono viu: #{resposta.presence || '(nenhuma, só Pronto)'}\n\n" \
            "Critério do que é certo: #{cena[:certo]}"
    cliente = Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve,
                                           feature: 'eval_juiz', account: conta)
    raw = cliente.create(model: AvaliacaoDoAjustePorLista::JUIZ, instructions: AvaliacaoDoAjustePorLista::INSTRUCAO_DO_JUIZ,
                         input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)],
                         schema: AvaliacaoDoAjustePorLista::VEREDITO)
    JSON.parse(raw[:text])
  end

  # O estado, pelo banco: aplicou quando devia, versão gravada só quando aplicou, campos fora do permitido iguais.
  def estado_certo?(cena, agente, antes, depois, estado)
    certo = case cena[:aplica]
            when false then nao_aplicou?(agente, antes, depois, estado)
            when true then aplicou_sem_falta?(cena, estado)
            when :nada then nada_visivel?(agente, antes, depois, estado)
            else estado['needs_more_info'] == true
            end
    certo && extras_certos?(cena, agente, antes, depois, estado)
  end

  def extras_certos?(cena, agente, antes, depois, estado)
    so_os_permitidos?(cena, antes, depois) && pendencia_certa?(cena, estado) && nada_desfeito?(cena, estado) &&
      informou_sem_perguntar?(cena, estado) && saudacao_certa?(cena, agente, estado)
  end

  # Nada mudou no agente e nenhuma versão do Construtor ficou na lista (pergunta, ou o desfeito do que ninguém pediu).
  def nada_visivel?(agente, antes, depois, estado)
    estado['applied'] != true && antes == depois &&
      agente.instruction_versions.na_lista.where(reason: 'builder_adjust').none?
  end

  def pendencia_certa?(cena, estado)
    case cena[:pendencia]
    when :resolvida then estado['pergunta_pendente'].to_s.empty?
    when :mantida then estado['pergunta_pendente'] == cena[:pendente]
    else true
    end
  end

  # A referência do não pedido vale só para o turno seguinte; a saudação volta só se o dono pediu.
  def saudacao_certa?(cena, agente, estado)
    return true unless cena[:tambem_mudei]

    esperada = cena[:saudacao] == :original ? 'Oi! Aqui é o Hubber, da Hub2You.' : AvaliacaoDoAjustePorLista::SAUDACAO_NAO_PEDIDA
    estado['nao_pedido_anterior'].nil? && agente.reload.greeting == esperada
  end

  def informou_sem_perguntar?(cena, estado)
    return true unless cena[:informa_sem_perguntar] && estado['conferencia'].to_h.key?('sem_pedido')

    estado['needs_more_info'] == false && estado['pergunta_pendente'].to_s.empty?
  end

  def nada_desfeito?(cena, estado)
    !cena[:nada_desfeito] || !estado['conferencia'].to_h.keys.intersect?(%w[desfeito sem_pedido])
  end

  def nao_aplicou?(agente, antes, depois, estado)
    estado['applied'] != true && estado['so_pergunta'] == true && antes == depois &&
      !agente.instruction_versions.exists?(reason: 'builder_adjust')
  end

  def aplicou_sem_falta?(cena, estado)
    atendidos = Array(estado.dig('conferencia', 'itens')).count { |item| item['atendido'] }
    estado['applied'] == true && estado.dig('conferencia', 'falta') == false && atendidos >= cena[:itens].to_i
  end

  def so_os_permitidos?(cena, antes, depois)
    cena[:so].nil? || (AvaliacaoDoAjustePorLista::CAMPOS_COMPARADOS - cena[:so]).all? { |campo| antes[campo] == depois[campo] }
  end

  def rodar(cena)
    agente, antes, depois, estado = ajustar(cena)
    resposta = estado['next_question'].to_s
    veredito = julgar(cena, antes, depois, resposta)
    { cena: cena[:nome], resposta: resposta, applied: estado['applied'], so_pergunta: estado['so_pergunta'],
      conferencia: estado['conferencia'], mudou: AvaliacaoDoAjustePorLista::CAMPOS_COMPARADOS.reject { |c| antes[c] == depois[c] },
      veredito: veredito, estado_certo: estado_certo?(cena, agente, antes, depois, estado),
      aprovada: estado_certo?(cena, agente, antes, depois, estado) && veredito['atende_o_certo'] &&
        !veredito['diz_pronto_sem_ter_feito'],
      custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  def cenas_escolhidas
    nome = ENV.fetch('AJUSTE_POR_LISTA_EVAL_CENA', nil).presence
    escolhidas = nome ? AvaliacaoDoAjustePorLista::CENAS.select { |cena| cena[:nome] == nome } : AvaliacaoDoAjustePorLista::CENAS
    expect(escolhidas).not_to be_empty, "cena desconhecida: #{nome}"
    escolhidas
  end

  it 'aplica o pedido inteiro, só ele, e nunca diz pronto sem ter feito' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['AJUSTE_POR_LISTA_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, AJUSTE_POR_LISTA_EVAL=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))

    cenas_escolhidas.each do |cena|
      break if custo_ate_agora >= AvaliacaoDoAjustePorLista::TETO_USD

      relatorio << rodar(cena)
    end

    destino = ENV.fetch('AJUSTE_POR_LISTA_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(custo_usd: custo_ate_agora.round(4), execucoes: relatorio)) if destino.present?
    expect(relatorio.size).to eq(cenas_escolhidas.size), "teto de custo atingido: #{relatorio.size} de #{cenas_escolhidas.size}"
    expect(relatorio.reject { |linha| linha[:aprovada] }.pluck(:cena)).to eq([])
  end
end
