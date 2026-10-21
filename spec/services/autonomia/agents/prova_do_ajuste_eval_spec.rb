require 'rails_helper'
require_relative 'prova_do_ajuste_eval_casos'

# AVALIAÇÃO PAGA DAS PERGUNTAS DE PROVA (#1428, tema 6: entrega B e termo t6d), DESLIGADA POR PADRÃO. Roda só com
# `AUTONOMIA_EVAL_PAGO=1`, `PROVA_DO_AJUSTE_EVAL=1` e `OPENAI_API_KEY`: o Construtor de verdade aplica o pedido e escreve
# as perguntas, o job da prova responde (sem ferramenta) e o juiz de produção dá o veredito. Um juiz de OUTRO modelo diz,
# pelo critério do caso, se as perguntas obedecem ao pedido (mostram a mudança), se alguma cita a instrução interna e se
# cada veredito de produção está certo. Os 20 casos (10 ramos) e os casos de controle ficam em prova_do_ajuste_eval_casos.rb,
# ao lado. t6d: pelo menos 18 de 20 aprovados (os controles contam à parte). Teto por rodada em
# `PROVA_DO_AJUSTE_EVAL_TETO_USD` (padrão US$ 0,90), somado pelo
# consumo gravado. Opcional: `PROVA_DO_AJUSTE_EVAL_SAIDA=<arquivo>` grava o relatório; `PROVA_DO_AJUSTE_EVAL_CENA=<a,b>`
# roda só esses casos.
module AvaliacaoDaProvaDoAjuste
  JUIZ = 'gpt-5.4'.freeze
  TETO_USD = 0.9

  VEREDITO = {
    name: 'veredito_prova_do_ajuste',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[perguntas_mostram_a_mudanca alguma_cita_instrucao vereditos_certos justificativa],
      properties: {
        perguntas_mostram_a_mudanca: { type: 'boolean', description: 'As mensagens de cliente, juntas, cumprem o critério ' \
                                                                     'do caso e fazem o agente mostrar as mudanças pedidas ' \
                                                                     'pelo dono?' },
        alguma_cita_instrucao: { type: 'boolean', description: 'Alguma mensagem de cliente cita ou parafraseia texto ' \
                                                               'interno de instrução, em vez de soar como um cliente?' },
        vereditos_certos: { type: 'array', items: { type: 'boolean' },
                            description: 'Para cada item, na ordem: os pedidos em testes são exatamente os que a mensagem ' \
                                         'testa (nenhum faltando, nenhum a mais) e o veredito de cada um (ok ou nao) está ' \
                                         'certo?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia um teste automático feito depois de um ajuste no agente de atendimento de um negócio. ' \
                      'Você recebe o pedido do dono, os pedidos que entraram no ajuste, o critério do caso (o que as ' \
                      'mensagens de teste precisam provocar), as mensagens de cliente escritas para testar, as respostas do ' \
                      'agente e, em cada item, os testes dados: cada pedido que a mensagem testa, com ok (a resposta respeita ' \
                      'o pedido) ou nao (a resposta contradiz ou ignora o pedido). Testes vazios querem dizer que a mensagem ' \
                      'não testa nenhum pedido. Um pedido de forma (tamanho, tom, emoji) é testado por qualquer resposta ' \
                      'escrita pelo agente; um pedido de assunto ou de gatilho, só quando a mensagem traz o assunto ou cria a ' \
                      'situação. No teste o agente não usa ferramentas. Responda cada campo pelo sentido, sem ser ' \
                      'generoso.'.freeze
end

RSpec.describe 'Avaliação paga das perguntas de prova (#1428)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) { conta_da_fase2 }
  let(:relatorio) { [] }
  let(:vereditos) { [] }
  # Os pedidos que o juiz de produção recebeu, por chamada (o texto de cada posição dos testes).
  let(:pedidos_do_juiz) { [] }
  # O texto fixo que o agente responde na prova do caso em curso (a armadilha); vazio, a IA responde.
  let(:resposta_fixa) { {} }

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def teto
    ENV.fetch('PROVA_DO_AJUSTE_EVAL_TETO_USD', AvaliacaoDaProvaDoAjuste::TETO_USD).to_f
  end

  def criar_agente(ramo)
    dados = AvaliacaoDaProvaDoAjuste::AGENTES.fetch(ramo)
    Autonomia::Agents::Agent.create!(
      account: conta, name: dados[:name], agent_type: 'support', mode: :guided, status: :active, enabled: true,
      instruction: dados[:instruction], tone: 'cordial e breve', greeting: dados[:greeting],
      fallback_message: 'Vou confirmar com a equipe e te retorno.', handoff_rule: 'Passe para a equipe quando o cliente pedir.',
      starter_questions: ['Como funciona?'], human_card: "#{dados[:name]} atende os clientes pelo WhatsApp.",
      config: { 'guardrails' => dados[:guardrails], 'voice' => 'feminina', 'with_knowledge' => false }
    )
  end

  def ajustar_e_provar(caso)
    thread = Autonomia::Agents::BuildThread.create!(account: conta, agent: criar_agente(caso[:agente]))
    thread.append_message!('user', caso[:fala])
    Autonomia::Agents::Builder.new(account: conta, build_thread: thread).run!(thread.begin_build!)
    preparar_prova(thread, caso)
    vereditos.clear
    pedidos_do_juiz.clear
    resposta_fixa[:texto] = caso[:resposta_fixa]
    perform_enqueued_jobs(only: Autonomia::Agents::ProvaDoAjusteJob)
    thread.reload.state.to_h
  ensure
    resposta_fixa.delete(:texto)
  end

  # A armadilha: só o agente em modo prova responde o texto do caso, sem chamar a IA.
  def resposta_fixa_na_prova
    allow(Autonomia::Agents::Answerer).to receive(:new).and_wrap_original do |original, **kwargs|
      texto = resposta_fixa[:texto]
      next original.call(**kwargs) unless texto && kwargs[:prova] == true

      resultado = Autonomia::Agents::AnswerResult.new(reply: texto, confidence: 0.9, handoff: { should: false, reason: nil }, error: nil)
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  def preparar_prova(thread, caso)
    acrescentar_pergunta(thread, caso[:extra]) if caso[:extra]
    trocar_perguntas(thread, caso[:perguntas_fixas]) if caso[:perguntas_fixas]
  end

  # A pergunta fora da mudança entra na prova pendente, como se o Construtor a tivesse escrito.
  def acrescentar_pergunta(thread, pergunta)
    estado = thread.reload.state
    return if estado['prova'].nil?

    prova = estado['prova'].merge('perguntas' => estado.dig('prova', 'perguntas') + [{ 'pergunta' => pergunta }])
    thread.update!(state: estado.merge('prova' => prova))
  end

  # O controle: as perguntas do Construtor são trocadas pelas do caso antes da prova.
  def trocar_perguntas(thread, perguntas)
    estado = thread.reload.state
    return if estado['prova'].nil?

    prova = estado['prova'].merge('perguntas' => perguntas.map { |pergunta| { 'pergunta' => pergunta } })
    thread.update!(state: estado.merge('prova' => prova))
  end

  def notas
    vereditos.last.to_a.pluck('veredito')
  end

  def pedidos_aplicados
    pedidos_do_juiz.last.to_a
  end

  # Os testes do juiz de produção para a pergunta, com o TEXTO do pedido no lugar da posição.
  def testes_com_texto(indice)
    Array(vereditos.last.to_a.dig(indice, 'testes')).map do |teste|
      { 'pedido' => pedidos_aplicados.dig(teste['pedido'], 'pedido'), 'veredito' => teste['veredito'] }
    end
  end

  def julgar(caso, prova)
    itens = Array(prova['perguntas']).each_with_index.map do |item, indice|
      { 'cliente' => item['pergunta'], 'agente' => item['resposta'], 'passa_para_equipe' => item['equipe'],
        'testes' => testes_com_texto(indice) }
    end
    texto = "Pedido do dono: #{caso[:fala]}\nPedidos que entraram: #{JSON.generate(pedidos_aplicados.pluck('pedido'))}\n" \
            "Critério do caso: #{caso[:obedece]}\n\nTeste:\n#{JSON.pretty_generate(itens)}"
    cliente = Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve,
                                           feature: 'eval_juiz', account: conta)
    raw = cliente.create(model: AvaliacaoDaProvaDoAjuste::JUIZ, instructions: AvaliacaoDaProvaDoAjuste::INSTRUCAO_DO_JUIZ,
                         input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)],
                         schema: AvaliacaoDaProvaDoAjuste::VEREDITO)
    JSON.parse(raw[:text])
  end

  # Estrutura (do código): o ajuste entrou, a prova ficou pronta com 1 a 3 perguntas do Construtor e pelo menos uma
  # tocou a mudança pelo juiz de produção. Julgamento (do juiz do eval): as perguntas obedecem ao critério, nenhuma cita a
  # instrução e cada veredito de produção está certo.
  def rodar(caso)
    estado = ajustar_e_provar(caso)
    prova = estado['prova'].to_h
    return rodar_controle(caso, estado, prova) if caso[:controle]

    veredito = prova['status'] == 'pronta' ? julgar(caso, prova) : {}
    { caso: caso[:nome], agente: caso[:agente], applied: estado['applied'], estrutura: estrutura_ok?(estado, prova, caso),
      prova: prova, vereditos_de_producao: vereditos.last, veredito: veredito,
      aprovada: estrutura_ok?(estado, prova, caso) && julgamento_ok?(veredito, prova) && fora_certa?(caso, prova),
      custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  # O controle sem `espera` não chama o juiz do eval: a estrutura basta. Os outros pedem a estrutura do caso e o juiz do
  # eval dizendo que cada pedido testado e o seu veredito estão certos. O relatório grava o texto do pedido de cada nao.
  def rodar_controle(caso, estado, prova)
    veredito = caso[:espera] && prova['status'] == 'pronta' ? julgar(caso, prova) : {}
    testes = Array(prova['perguntas']).each_index.map { |indice| testes_com_texto(indice) }
    { caso: caso[:nome], agente: caso[:agente], controle: true, applied: estado['applied'], prova: prova,
      pedidos_aplicados: pedidos_aplicados.pluck('pedido'), testes: testes, veredito: veredito,
      pedidos_do_nao: testes.flatten.select { |teste| teste['veredito'] == 'nao' }.pluck('pedido').uniq,
      aprovada: controle_ok?(caso, prova, veredito), custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  # Sem `espera`: pronta e sem prova completa. `:teste_nao`: 2+ pedidos e uma mesma pergunta com um ok e um nao.
  # `:so_forma`: 2+ pedidos, alguma pergunta testa, e um pedido fica fora de todos os testes. `:julgado`: completa. Os três
  # últimos pedem o juiz do eval de acordo com cada teste (qual pedido levou o nao, qual ficou de fora).
  def controle_ok?(caso, prova, veredito)
    return false unless prova['status'] == 'pronta'
    return prova['completa'] == false if caso[:espera].nil?

    estrutura = { teste_nao: ok_e_nao_na_mesma_pergunta?(prova), so_forma: um_pedido_fora?(prova),
                  julgado: prova['total'].to_i >= 1 && prova['completa'] == true }.fetch(caso[:espera])
    estrutura && vereditos_certos?(veredito, prova)
  end

  def ok_e_nao_na_mesma_pergunta?(prova)
    ok_e_nao = %w[ok nao]
    pedidos_aplicados.size >= 2 && Array(prova['perguntas']).any? do |item|
      (ok_e_nao - Array(item['testes']).pluck('veredito')).empty?
    end
  end

  def um_pedido_fora?(prova)
    testados = Array(prova['perguntas']).flat_map { |item| Array(item['testes']).pluck('pedido') }.uniq
    prova['total'].to_i >= 1 && pedidos_aplicados.size >= 2 && testados.size == pedidos_aplicados.size - 1
  end

  # Estrutura (do código): o ajuste entrou, a prova ficou pronta com 1 a 3 perguntas do Construtor, pelo menos uma tocou a
  # mudança e cada pedido teve uma pergunta que o testou (`completa`, pelo juiz de produção).
  def estrutura_ok?(estado, prova, caso)
    escritas = Array(prova['perguntas']).size - (caso[:extra] ? 1 : 0)
    estado['applied'] == true && prova['status'] == 'pronta' && escritas.between?(1, 3) && prova['total'].to_i >= 1 &&
      prova['completa'] == true
  end

  def julgamento_ok?(veredito, prova)
    veredito['perguntas_mostram_a_mudanca'] == true && veredito['alguma_cita_instrucao'] == false &&
      vereditos_certos?(veredito, prova)
  end

  # Um julgamento certo por pergunta, nem mais nem menos.
  def vereditos_certos?(veredito, prova)
    certos = Array(veredito['vereditos_certos'])
    certos.size == Array(prova['perguntas']).size && certos.all?(true)
  end

  # A pergunta fora da mudança (a última) ficou fora do placar.
  def fora_certa?(caso, prova)
    return true unless caso[:extra]

    notas.last == 'nao_testa' && prova['total'].to_i < Array(prova['perguntas']).size
  end

  def casos_escolhidos
    nomes = ENV.fetch('PROVA_DO_AJUSTE_EVAL_CENA', '').split(',').map(&:strip).compact_blank
    escolhidos = AvaliacaoDaProvaDoAjuste::CASOS
    escolhidos = escolhidos.select { |caso| nomes.include?(caso[:nome]) } if nomes.any?
    expect(escolhidos.size).to eq(nomes.any? ? nomes.size : AvaliacaoDaProvaDoAjuste::CASOS.size), "caso desconhecido: #{nomes}"
    escolhidos
  end

  def gravar_relatorio
    destino = ENV.fetch('PROVA_DO_AJUSTE_EVAL_SAIDA', nil)
    return if destino.blank?

    casos, controles = relatorio.partition { |linha| linha[:controle].nil? }
    File.write(destino, JSON.pretty_generate(custo_usd: custo_ate_agora.round(4), aprovados: casos.count { |linha| linha[:aprovada] },
                                             rodados: casos.size, controles_ok: controles.count { |linha| linha[:aprovada] },
                                             controles: controles.size, execucoes: relatorio))
  end

  it 'escreve perguntas que obedecem ao pedido, responde sem ferramenta e julga certo' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['PROVA_DO_AJUSTE_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, PROVA_DO_AJUSTE_EVAL=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    allow_any_instance_of(Autonomia::Agents::JuizDaProva).to receive(:julgar).and_wrap_original do |original, **kwargs| # rubocop:disable RSpec/AnyInstance
      pedidos_do_juiz << kwargs[:pedidos]
      original.call(**kwargs).tap { |saida| vereditos << saida }
    end
    resposta_fixa_na_prova

    casos = casos_escolhidos
    casos.each do |caso|
      break if custo_ate_agora >= teto

      relatorio << rodar(caso)
    end

    gravar_relatorio
    expect(relatorio.size).to eq(casos.size), "teto de custo atingido: #{relatorio.size} de #{casos.size}"
    expect(relatorio.reject { |linha| linha[:aprovada] }.pluck(:caso)).to eq([])
  end
end
