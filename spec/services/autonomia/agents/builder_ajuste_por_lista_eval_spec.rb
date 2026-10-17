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
  TETO_USD = 1.8
  CAMPOS_COMPARADOS = %w[name instruction tone greeting fallback_message handoff_rule starter_questions human_card
                         guardrails voice].freeze

  HUBBER = <<~TXT.freeze
    Você é o Hubber, assistente da Hub2You, uma corretora de seguros. Atenda pelo WhatsApp com cordialidade e seja
    breve. Explique os tipos de seguro (auto, residencial e vida) e colete nome, cidade e o seguro de interesse. Quando o
    cliente pedir para falar com uma pessoa, passe para a equipe. Nunca invente valores, coberturas ou prazos.
  TXT

  # Cada cena: a fala do dono e o que é certo. `aplica`: se a cena deve gravar algo. `so` (opcional): os únicos campos
  # que podem mudar. `itens` (opcional): quantos pedidos a conferência tem de dar como atendidos.
  CENAS = [
    { nome: 't6a_duas_frases_e_preco', fala: 'Responda em no máximo 2 frases e preço passa para a equipe.', aplica: true, itens: 2,
      certo: 'O agente DEPOIS limita as respostas a no máximo 2 frases (no tom e na instrução) E passa para a equipe quando ' \
             'o cliente pergunta preço (na regra de passagem). As duas coisas.' },
    { nome: 'explica_o_que_faz', fala: 'Me explica o que o Hubber faz hoje', aplica: false,
      certo: 'É só uma pergunta: nada muda no agente, e a resposta ao dono explica o que o Hubber faz hoje, sem dizer que ' \
             'mudou ou aplicou algo.' },
    { nome: 't6b_contraditorio', fala: 'Responda sempre com uma palavra só e explique cada seguro em detalhes, com ' \
                                       'todas as coberturas.', aplica: nil,
      certo: 'O pedido é contraditório: a resposta ao dono pergunta ou esclarece qual das duas coisas ele quer, e não ' \
             'diz que está pronto nem que aplicou tudo.' },
    { nome: 't6c_so_o_tom', fala: 'Deixe o tom mais formal, trate o cliente por senhor ou senhora.', aplica: true,
      so: %w[tone instruction human_card],
      certo: 'O agente DEPOIS tem tom formal e trata o cliente por senhor ou senhora. Saudação, nome, voz, regra de ' \
             'passagem, mensagem de fallback e perguntas iniciais iguais às de antes.' },
    { nome: 'nao_fale_de_preco', fala: 'Não fale de preço com o cliente.', aplica: true,
      certo: 'O agente DEPOIS tem escrito que não fala de preço com o cliente (nos limites e na instrução), mesmo já ' \
             'tendo a regra geral de não inventar valores.' },
    { nome: 'troca_a_saudacao', fala: 'Troque a saudação para: Olá! Aqui é o Hubber, da Hub2You. Em que posso ajudar?',
      aplica: true, so: %w[greeting],
      certo: 'Só a saudação muda, para a frase pedida. Todo o resto do agente fica igual.' }
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
    thread.append_message!('user', cena[:fala])
    Autonomia::Agents::Builder.new(account: conta, build_thread: thread).run!(thread.begin_build!)
    [agente, antes, retrato(agente), thread.reload.state.to_h]
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
            else estado['needs_more_info'] == true
            end
    certo && so_os_permitidos?(cena, antes, depois)
  end

  def nao_aplicou?(agente, antes, depois, estado)
    estado['applied'] != true && estado['so_pergunta'] == true && antes == depois &&
      !agente.instruction_versions.exists?(reason: 'builder_adjust')
  end

  def aplicou_sem_falta?(cena, estado)
    atendidos = Array(estado.dig('conferencia', 'itens')).count { |item| item['atendido'] }
    estado['applied'] == true && Array(estado.dig('conferencia', 'pendencias')).empty? && atendidos >= cena[:itens].to_i
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
