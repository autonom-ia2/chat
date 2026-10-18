require 'rails_helper'

# AVALIAÇÃO PAGA DAS PERGUNTAS DE PROVA (#1428, tema 6, parte 3, entrega B), DESLIGADA POR PADRÃO. Roda só com
# `AUTONOMIA_EVAL_PAGO=1`, `PROVA_DO_AJUSTE_EVAL=1` e `OPENAI_API_KEY`: o Construtor de verdade aplica o pedido e escreve
# as perguntas, o job da prova responde (sem ferramenta) e o juiz de produção dá o veredito. Um juiz de OUTRO modelo diz
# se as perguntas mostram a mudança, se alguma cita a instrução interna e se cada veredito de produção está certo.
# Teto de US$ 0,90 por rodada (somado pelo consumo gravado). Opcional: `PROVA_DO_AJUSTE_EVAL_SAIDA=<arquivo>` grava o
# relatório; `PROVA_DO_AJUSTE_EVAL_CENA=<nome>` roda só uma cena.
module AvaliacaoDaProvaDoAjuste
  JUIZ = 'gpt-5.4'.freeze
  TETO_USD = 0.9

  HUBBER = <<~TXT.freeze
    Você é o Hubber, assistente da Hub2You, uma corretora de seguros. Atenda pelo WhatsApp com cordialidade e seja
    breve. Explique os tipos de seguro (auto, residencial e vida) e colete nome, cidade e o seguro de interesse. Quando o
    cliente pedir para falar com uma pessoa, passe para a equipe. Nunca invente valores, coberturas ou prazos.
  TXT

  CENAS = [
    { nome: 'prova_duas_frases_e_preco', fala: 'Responda em no máximo 2 frases e preço passa para a equipe.' },
    { nome: 'prova_tom_formal', fala: 'Deixe o tom mais formal, trate o cliente por senhor ou senhora.' },
    { nome: 'prova_sem_seguro_viagem', fala: 'Quando perguntarem de seguro viagem, diga que a Hub2You não trabalha com esse ' \
                                             'tipo e ofereça os que temos.' },
    # Revisão (MÉDIA): uma pergunta que não toca a mudança entra na prova e não pode virar ✓.
    { nome: 'prova_pergunta_fora_da_mudanca', fala: 'Quando perguntarem preço, passe para a equipe.',
      extra: 'Vocês atendem em Curitiba?' }
  ].freeze

  VEREDITO = {
    name: 'veredito_prova_do_ajuste',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[perguntas_mostram_a_mudanca alguma_cita_instrucao vereditos_certos justificativa],
      properties: {
        perguntas_mostram_a_mudanca: { type: 'boolean', description: 'As mensagens de cliente, juntas, fazem o agente ' \
                                                                     'mostrar as mudanças pedidas pelo dono?' },
        alguma_cita_instrucao: { type: 'boolean', description: 'Alguma mensagem de cliente cita ou parafraseia texto ' \
                                                               'interno de instrução, em vez de soar como um cliente?' },
        vereditos_certos: { type: 'array', items: { type: 'boolean' },
                            description: 'Para cada item, na ordem: o veredito dado (ok, nao ou nao_testa) está certo?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia um teste automático feito depois de um ajuste no agente de atendimento de uma corretora. ' \
                      'Você recebe o pedido do dono, as mensagens de cliente escritas para testar, as respostas do agente e ' \
                      'o veredito dado a cada resposta: ok (a mensagem toca a mudança e a resposta a respeita), nao (toca e a resposta ' \
                      'contradiz ou ignora) ou nao_testa (a mensagem não toca nenhuma mudança). No teste o agente não usa ' \
                      'ferramentas. Responda cada campo pelo sentido, sem ser generoso.'.freeze
end

RSpec.describe 'Avaliação paga das perguntas de prova (#1428)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) { conta_da_fase2 }
  let(:relatorio) { [] }
  let(:vereditos) { [] }

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
      instruction: AvaliacaoDaProvaDoAjuste::HUBBER, tone: 'cordial e breve', greeting: 'Oi! Aqui é o Hubber, da Hub2You.',
      fallback_message: 'Vou confirmar com a equipe e te retorno.', handoff_rule: 'Passe para a equipe quando o cliente pedir.',
      starter_questions: ['Quais seguros vocês têm?'], human_card: 'O Hubber atende os clientes da Hub2You.',
      config: { 'guardrails' => ['Nunca invente valores, coberturas ou prazos.'], 'voice' => 'masculina',
                'with_knowledge' => false }
    )
  end

  def ajustar_e_provar(cena)
    thread = Autonomia::Agents::BuildThread.create!(account: conta, agent: criar_hubber)
    thread.append_message!('user', cena[:fala])
    Autonomia::Agents::Builder.new(account: conta, build_thread: thread).run!(thread.begin_build!)
    acrescentar_pergunta(thread, cena[:extra]) if cena[:extra]
    vereditos.clear
    perform_enqueued_jobs(only: Autonomia::Agents::ProvaDoAjusteJob)
    thread.reload.state.to_h
  end

  # A pergunta fora da mudança entra na prova pendente, como se o Construtor a tivesse escrito.
  def acrescentar_pergunta(thread, pergunta)
    estado = thread.reload.state
    prova = estado['prova'].merge('perguntas' => estado.dig('prova', 'perguntas') + [{ 'pergunta' => pergunta }])
    thread.update!(state: estado.merge('prova' => prova))
  end

  def julgar(cena, prova)
    itens = Array(prova['perguntas']).each_with_index.map do |item, indice|
      { 'cliente' => item['pergunta'], 'agente' => item['resposta'], 'passa_para_equipe' => item['equipe'],
        'veredito' => vereditos.last.to_a[indice] }
    end
    texto = "Pedido do dono: #{cena[:fala]}\n\nTeste:\n#{JSON.pretty_generate(itens)}"
    cliente = Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve,
                                           feature: 'eval_juiz', account: conta)
    raw = cliente.create(model: AvaliacaoDaProvaDoAjuste::JUIZ, instructions: AvaliacaoDaProvaDoAjuste::INSTRUCAO_DO_JUIZ,
                         input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)],
                         schema: AvaliacaoDaProvaDoAjuste::VEREDITO)
    JSON.parse(raw[:text])
  end

  def rodar(cena)
    estado = ajustar_e_provar(cena)
    prova = estado['prova'].to_h
    veredito = prova['status'] == 'pronta' ? julgar(cena, prova) : {}
    pronta = prova['status'] == 'pronta' && Array(prova['perguntas']).size.between?(1, 3)
    { cena: cena[:nome], applied: estado['applied'], prova: prova, vereditos_de_producao: vereditos.last, veredito: veredito,
      aprovada: pronta && veredito['perguntas_mostram_a_mudanca'] == true && veredito['alguma_cita_instrucao'] == false &&
        Array(veredito['vereditos_certos']).all? && fora_certa?(cena, prova),
      custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  # A pergunta fora da mudança (a última) ficou fora do placar.
  def fora_certa?(cena, prova)
    return true unless cena[:extra]

    vereditos.last.to_a.last == 'nao_testa' && prova['total'] < Array(prova['perguntas']).size
  end

  def cenas_escolhidas
    nome = ENV.fetch('PROVA_DO_AJUSTE_EVAL_CENA', nil).presence
    escolhidas = nome ? AvaliacaoDaProvaDoAjuste::CENAS.select { |cena| cena[:nome] == nome } : AvaliacaoDaProvaDoAjuste::CENAS
    expect(escolhidas).not_to be_empty, "cena desconhecida: #{nome}"
    escolhidas
  end

  it 'escreve perguntas que mostram a mudança, responde sem ferramenta e julga certo' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['PROVA_DO_AJUSTE_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, PROVA_DO_AJUSTE_EVAL=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    allow_any_instance_of(Autonomia::Agents::JuizDaProva).to receive(:julgar).and_wrap_original do |original, **kwargs| # rubocop:disable RSpec/AnyInstance
      original.call(**kwargs).tap { |saida| vereditos << saida }
    end

    cenas_escolhidas.each do |cena|
      break if custo_ate_agora >= AvaliacaoDaProvaDoAjuste::TETO_USD

      relatorio << rodar(cena)
    end

    destino = ENV.fetch('PROVA_DO_AJUSTE_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(custo_usd: custo_ate_agora.round(4), execucoes: relatorio)) if destino.present?
    expect(relatorio.size).to eq(cenas_escolhidas.size), "teto de custo atingido: #{relatorio.size} de #{cenas_escolhidas.size}"
    expect(relatorio.reject { |linha| linha[:aprovada] }.pluck(:cena)).to eq([])
  end
end
