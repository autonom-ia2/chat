require 'rails_helper'
require_relative 'prova_do_ajuste_eval_casos'

# AVALIAÇÃO PAGA DAS PERGUNTAS DE PROVA (#1428, tema 6: entrega B e termo t6d), DESLIGADA POR PADRÃO. Roda só com
# `AUTONOMIA_EVAL_PAGO=1`, `PROVA_DO_AJUSTE_EVAL=1` e `OPENAI_API_KEY`.
#   - Os 21 casos (10 ramos; um com base de conhecimento ligada): o Construtor de verdade aplica o pedido e escreve as
#     perguntas, o job da prova responde (sem ferramenta, com a base quando ligada) e o juiz de produção dá os testes.
#     Um juiz de OUTRO modelo diz, pelo critério do caso, se as perguntas obedecem ao pedido, se alguma cita a
#     instrução interna e se cada teste de produção está certo. A regra de referência dele para os testes é a do juiz
#     de produção, lida da constante (JuizDaProva::INSTRUCAO), sem cópia.
#   - Os controles (fora dos casos): só o juiz de produção, com pedidos e respostas fixos, REPETICOES_DO_CONTROLE vezes.
#   - `PROVA_DO_AJUSTE_EVAL_REJULGAR=<relatorio.json>`: lê um relatório gravado e chama SÓ o juiz do eval de novo
#     (os casos; sem Construtor, sem prova, sem controle), com o retrato do agente que o juiz de produção recebeu.
# t6d: pelo menos 18 de 20 aprovados (com o caso da base, 19 de 21; ver o doc), com todos os controles certos nas repetições. Teto por rodada em
# `PROVA_DO_AJUSTE_EVAL_TETO_USD` (padrão US$ 0,90), somado pelo consumo gravado. Opcional:
# `PROVA_DO_AJUSTE_EVAL_SAIDA=<arquivo>` grava o relatório; `PROVA_DO_AJUSTE_EVAL_CENA=<a,b>` roda só esses casos ou
# controles. A régua (critérios e os dois juízes) fica congelada num commit registrado no doc antes de rodar.
module AvaliacaoDaProvaDoAjuste
  JUIZ = 'gpt-5.4'.freeze
  TETO_USD = 0.9
  REPETICOES_DO_CONTROLE = 3

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
                            description: 'Para cada item, na ordem: pela REGRA DE REFERENCIA, os pedidos em testes são ' \
                                         'exatamente os que a mensagem testa (nenhum faltando, nenhum a mais) e o veredito ' \
                                         'de cada um (ok ou nao) está certo?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  # Forense do t6d (M1): a régua dos testes é a do juiz de produção, a mesma constante, nunca uma cópia que se desvia.
  PAPEL_DO_JUIZ =
    'Você avalia um teste automático feito depois de um ajuste no agente de atendimento de um negócio. Você recebe o ' \
    'pedido do dono, os campos que o agente tem escritos, os pedidos que entraram no ajuste, o critério do caso (o que as ' \
    'mensagens de teste precisam provocar), as mensagens de cliente escritas para testar, as respostas do agente e, em ' \
    'cada item, os testes dados pelo juiz de produção: cada pedido que a mensagem testa, com ok ou nao. Para dizer se os ' \
    'testes estão certos, use a REGRA DE REFERENCIA abaixo, que é a do juiz de produção. No teste o agente não usa ' \
    'ferramentas; quando tem base de conhecimento, busca nela, e os trechos que a resposta usou vêm no item: um fato ' \
    'presente neles conta como sabido. Responda cada campo pelo sentido, sem ser generoso.'.freeze
  INSTRUCAO_DO_JUIZ = "#{PAPEL_DO_JUIZ}\n\nREGRA DE REFERENCIA:\n#{Autonomia::Agents::JuizDaProva::INSTRUCAO}".freeze
end

RSpec.describe 'Avaliação paga das perguntas de prova (#1428)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) { conta_da_fase2 }
  let(:relatorio) { [] }
  # Os pedidos que o juiz de produção recebeu, por chamada (o texto de cada posição dos testes).
  let(:pedidos_do_juiz) { [] }
  # O retrato do agente que o juiz de produção recebeu (o de depois do ajuste): o juiz do eval lê o mesmo.
  let(:agentes_do_juiz) { [] }

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def ligada?
    ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['PROVA_DO_AJUSTE_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
  end

  def ligar_a_chave!
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def teto
    ENV.fetch('PROVA_DO_AJUSTE_EVAL_TETO_USD', AvaliacaoDaProvaDoAjuste::TETO_USD).to_f
  end

  def criar_agente(ramo, base = nil)
    dados = AvaliacaoDaProvaDoAjuste::AGENTES.fetch(ramo)
    Autonomia::Agents::Agent.create!(
      account: conta, name: dados[:name], agent_type: 'support', mode: :guided, status: :active, enabled: true,
      instruction: dados[:instruction], tone: AvaliacaoDaProvaDoAjuste::TOM, greeting: dados[:greeting],
      fallback_message: AvaliacaoDaProvaDoAjuste::MENSAGEM_FIXA, handoff_rule: AvaliacaoDaProvaDoAjuste::REGRA_DE_PASSAGEM,
      starter_questions: ['Como funciona?'], human_card: "#{dados[:name]} atende os clientes pelo WhatsApp.",
      config: { 'guardrails' => dados[:guardrails], 'voice' => 'feminina', 'with_knowledge' => base.present? }
    ).tap { |agente| criar_base(agente, base) if base.present? }
  end

  # A base do caso, lida e aprovada, um trecho por entrada, com o vetor de verdade (o Retriever da prova a encontra).
  def criar_base(agente, trechos)
    fonte = Autonomia::Agents::Source.create!(account: conta, agent: agente, source_type: 'txt', reference: 'base.txt',
                                              status: :ready, review_status: 'accepted', reviewed_at: Time.current,
                                              review_summary: trechos.first, metadata: {})
    vetores = Autonomia::Agents::EmbeddingService.new(account: conta).embed_batch(trechos)
    trechos.zip(vetores).each_with_index do |(trecho, vetor), indice|
      Autonomia::Agents::KnowledgeEntry.create!(account: conta, agent: agente, source: fonte, status: :ready,
                                                chunk_index: indice, content: trecho, embedding: vetor)
    end
  end

  # Os campos do agente do ramo que o juiz de produção e o do eval leem (ProvaDoAjuste::CAMPOS_PARA_O_JUIZ).
  def campos_do_agente(ramo)
    dados = AvaliacaoDaProvaDoAjuste::AGENTES.fetch(ramo)
    { 'instruction' => dados[:instruction], 'tone' => AvaliacaoDaProvaDoAjuste::TOM, 'greeting' => dados[:greeting],
      'fallback_message' => AvaliacaoDaProvaDoAjuste::MENSAGEM_FIXA,
      'handoff_rule' => AvaliacaoDaProvaDoAjuste::REGRA_DE_PASSAGEM, 'guardrails' => dados[:guardrails] }
  end

  def ajustar_e_provar(caso)
    thread = Autonomia::Agents::BuildThread.create!(account: conta, agent: criar_agente(caso[:agente], caso[:base]))
    thread.append_message!('user', caso[:fala])
    Autonomia::Agents::Builder.new(account: conta, build_thread: thread).run!(thread.begin_build!)
    acrescentar_pergunta(thread, caso[:extra]) if caso[:extra]
    pedidos_do_juiz.clear
    agentes_do_juiz.clear
    perform_enqueued_jobs(only: Autonomia::Agents::ProvaDoAjusteJob)
    thread.reload.state.to_h
  end

  # A pergunta fora da mudança entra na prova pendente, como se o Construtor a tivesse escrito.
  def acrescentar_pergunta(thread, pergunta)
    estado = thread.reload.state
    return if estado['prova'].nil?

    prova = estado['prova'].merge('perguntas' => estado.dig('prova', 'perguntas') + [{ 'pergunta' => pergunta }])
    thread.update!(state: estado.merge('prova' => prova))
  end

  # Os testes gravados na prova, com o TEXTO do pedido no lugar da posição.
  def testes_com_texto(item, pedidos)
    Array(item['testes']).map { |teste| { 'pedido' => pedidos[teste['pedido'].to_i], 'veredito' => teste['veredito'] } }
  end

  # O juiz do eval lê só o que ficou gravado: a prova, os pedidos aplicados e o retrato que o juiz de produção recebeu
  # (o do ramo, em relatório antigo sem ele). Serve ao rejulgar.
  def julgar(caso, prova, pedidos, agente = nil)
    itens = Array(prova['perguntas']).map do |item|
      { 'cliente' => item['pergunta'], 'agente' => item['resposta'], 'passa_para_equipe' => item['equipe'],
        'trechos_da_base_usados' => Array(item['trechos']), 'testes' => testes_com_texto(item, pedidos) }
    end
    campos = agente.presence || campos_do_agente(caso[:agente])
    texto = "Pedido do dono: #{caso[:fala]}\nCampos do agente: #{JSON.generate(campos)}\n" \
            "Pedidos que entraram: #{JSON.generate(pedidos)}\nCritério do caso: #{caso[:obedece]}\n\n" \
            "Teste:\n#{JSON.pretty_generate(itens)}"
    JSON.parse(cliente_do_eval.create(model: AvaliacaoDaProvaDoAjuste::JUIZ, schema: AvaliacaoDaProvaDoAjuste::VEREDITO,
                                      instructions: AvaliacaoDaProvaDoAjuste::INSTRUCAO_DO_JUIZ,
                                      input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)])[:text])
  end

  def cliente_do_eval
    Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve, feature: 'eval_juiz',
                                 account: conta)
  end

  def rodar(caso)
    estado = ajustar_e_provar(caso)
    prova = estado['prova'].to_h
    pedidos = pedidos_do_juiz.last.to_a.pluck('pedido')
    agente = agentes_do_juiz.last.to_h
    veredito = prova['status'] == 'pronta' ? julgar(caso, prova, pedidos, agente) : {}
    linha(caso, estado['applied'], prova, pedidos, veredito).merge(agente_do_juiz: agente)
  end

  # Estrutura (do código): o ajuste entrou, a prova ficou pronta com 1 a 3 perguntas do Construtor, pelo menos uma tocou a
  # mudança e cada pedido teve um teste (`completa`). Julgamento (do juiz do eval): critério, sigilo e cada teste certo.
  def linha(caso, applied, prova, pedidos, veredito)
    estrutura = estrutura_ok?(applied, prova, caso)
    { caso: caso[:nome], agente: caso[:agente], applied: applied, estrutura: estrutura, prova: prova,
      pedidos_aplicados: pedidos, veredito: veredito, declarado_x_testado: declarado_x_testado(prova, pedidos),
      aprovada: estrutura && julgamento_ok?(veredito, prova) && fora_certa?(caso, prova),
      custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  # Revisão do t6d (MÉDIO 5), só informativo: o pedido que o Construtor declarou em cada mensagem e os pedidos que o juiz
  # de produção deu como testados. Não entra na aprovação: os dois vêm do mesmo produto (limitação no doc).
  def declarado_x_testado(prova, pedidos)
    Array(prova['perguntas']).map do |item|
      testados = testes_com_texto(item, pedidos).pluck('pedido')
      { 'pergunta' => item['pergunta'], 'declarado' => item['pedido'], 'testados' => testados,
        'declarado_testado' => item['pedido'].nil? ? nil : testados.include?(item['pedido']) }
    end
  end

  def estrutura_ok?(applied, prova, caso)
    escritas = Array(prova['perguntas']).size - (caso[:extra] ? 1 : 0)
    applied == true && prova['status'] == 'pronta' && escritas.between?(1, 3) && prova['total'].to_i >= 1 &&
      prova['completa'] == true
  end

  def julgamento_ok?(veredito, prova)
    certos = Array(veredito['vereditos_certos'])
    veredito['perguntas_mostram_a_mudanca'] == true && veredito['alguma_cita_instrucao'] == false &&
      certos.size == Array(prova['perguntas']).size && certos.all?(true)
  end

  # A pergunta fora da mudança (a última) ficou fora do placar.
  def fora_certa?(caso, prova)
    return true unless caso[:extra]

    perguntas = Array(prova['perguntas'])
    perguntas.last.to_h['veredito'] == 'nao_testa' && prova['total'].to_i < perguntas.size
  end

  # Forense do t6d (M2): o controle chama só o juiz de produção, com o que está fixo no caso, várias vezes.
  def rodar_controle(controle)
    pedidos = controle[:pedidos].each_with_index.map { |texto, posicao| { 'numero' => posicao + 1, 'pedido' => texto, 'o_que_mudou' => [texto] } }
    rodadas = Array.new(AvaliacaoDaProvaDoAjuste::REPETICOES_DO_CONTROLE) do
      saida = Autonomia::Agents::JuizDaProva.new(account: conta)
                                            .julgar(pedidos: pedidos, itens: controle[:itens], agente: campos_do_agente(controle[:agente]))
      rodada_do_controle(controle, saida)
    end
    { caso: controle[:nome], controle: true, pedidos_aplicados: controle[:pedidos], rodadas: rodadas,
      aprovada: rodadas.all? { |rodada| rodada[:certa] }, custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  def rodada_do_controle(controle, saida)
    testes = Array(saida).flat_map { |nota| nota['testes'] }
    { saida: saida, certa: !saida.nil? && espera_cumprida?(controle[:espera], testes),
      pedidos_do_nao: testes.select { |teste| teste['veredito'] == 'nao' }.map { |teste| controle[:pedidos][teste['pedido']] } }
  end

  def espera_cumprida?(espera, testes)
    vereditos_esperados?(espera, testes) && presencas_esperadas?(espera, testes.pluck('pedido'))
  end

  def vereditos_esperados?(espera, testes)
    %w[nao ok].all? do |veredito|
      Array(espera[veredito.to_sym]).all? { |posicao| testes.include?('pedido' => posicao, 'veredito' => veredito) }
    end
  end

  def presencas_esperadas?(espera, testados)
    Array(espera[:presentes]).all? { |posicao| testados.include?(posicao) } &&
      Array(espera[:ausentes]).none? { |posicao| testados.include?(posicao) }
  end

  def escolhidos(lista)
    nomes = ENV.fetch('PROVA_DO_AJUSTE_EVAL_CENA', '').split(',').map(&:strip).compact_blank
    nomes.any? ? lista.select { |caso| nomes.include?(caso[:nome]) } : lista
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
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, PROVA_DO_AJUSTE_EVAL=1 e OPENAI_API_KEY' unless ligada?
    skip 'modo rejulgar' if ENV['PROVA_DO_AJUSTE_EVAL_REJULGAR'].present?

    ligar_a_chave!
    allow_any_instance_of(Autonomia::Agents::JuizDaProva).to receive(:julgar).and_wrap_original do |original, **kwargs| # rubocop:disable RSpec/AnyInstance
      pedidos_do_juiz << kwargs[:pedidos]
      agentes_do_juiz << kwargs[:agente]
      original.call(**kwargs)
    end
    todos = escolhidos(AvaliacaoDaProvaDoAjuste::CASOS) + escolhidos(AvaliacaoDaProvaDoAjuste::CONTROLES)
    todos.each do |caso|
      break if custo_ate_agora >= teto

      relatorio << (caso.key?(:espera) ? rodar_controle(caso) : rodar(caso))
    end

    gravar_relatorio
    expect(relatorio.size).to eq(todos.size), "teto de custo atingido: #{relatorio.size} de #{todos.size}"
    expect(relatorio.reject { |linha| linha[:aprovada] }.pluck(:caso)).to eq([])
  end

  # Sem custo (roda sempre): a régua dos controles aprova a saída certa e reprova a errada, nas repetições.
  describe 'a régua dos controles, com o juiz de produção dublado' do
    def controle(nome)
      AvaliacaoDaProvaDoAjuste::CONTROLES.find { |candidato| candidato[:nome] == nome }
    end

    def juiz_devolve(*saidas)
      juiz = instance_double(Autonomia::Agents::JuizDaProva)
      allow(Autonomia::Agents::JuizDaProva).to receive(:new).and_return(juiz)
      allow(juiz).to receive(:julgar).and_return(*saidas)
      juiz
    end

    def nota(*testes)
      { 'veredito' => testes.empty? ? 'nao_testa' : 'ok',
        'testes' => testes.map { |pedido, veredito| { 'pedido' => pedido, 'veredito' => veredito } } }
    end

    it 'emoji: aprova o nao no pedido do emoji nas 3 vezes, grava o texto do pedido e reprova se uma vez falhar' do
      juiz = juiz_devolve([nota([0, 'ok'], [1, 'nao'])])
      certo = rodar_controle(controle('controle_emoji'))
      juiz_devolve([nota([0, 'ok'], [1, 'nao'])], [nota([0, 'ok'], [1, 'nao'])], [nota([0, 'ok'], [1, 'ok'])])
      errado = rodar_controle(controle('controle_emoji'))

      expect(juiz).to have_received(:julgar).exactly(3).times.with(hash_including(agente: hash_including('fallback_message')))
      expect(certo).to include(aprovada: true, pedidos_aplicados: ['Responda de forma curta', 'Não use emoji'])
      expect(certo[:rodadas].first[:pedidos_do_nao]).to eq(['Não use emoji'])
      expect(errado[:aprovada]).to be(false)
    end

    it 'preço: aprova só com a forma testada e o preço fora de todos os testes; saída indisponível reprova' do
      juiz_devolve([nota([0, 'ok']), nota([0, 'ok'])])
      expect(rodar_controle(controle('controle_preco'))[:aprovada]).to be(true)
      juiz_devolve([nota([0, 'ok'], [1, 'ok']), nota])
      expect(rodar_controle(controle('controle_preco'))[:aprovada]).to be(false)
      juiz_devolve(nil)
      expect(rodar_controle(controle('controle_preco'))[:aprovada]).to be(false)
    end

    it 'gatilho: aprova o ok no pedido da situação; sem teste, reprova' do
      juiz_devolve([nota([0, 'ok'])])
      expect(rodar_controle(controle('controle_gatilho'))[:aprovada]).to be(true)
      juiz_devolve([nota])
      expect(rodar_controle(controle('controle_gatilho'))[:aprovada]).to be(false)
    end
  end

  # Sem custo: o rejulgar lê o relatório gravado e só o juiz do eval é chamado, com a régua de produção na instrução.
  it 'rejulgar: lê o relatório, manda os testes com o texto do pedido e recalcula a aprovação' do
    caso = AvaliacaoDaProvaDoAjuste::CASOS.first
    prova = { 'status' => 'pronta', 'total' => 1, 'ok' => 1, 'completa' => true,
              'perguntas' => [{ 'pergunta' => 'Oi', 'resposta' => 'Olá.', 'equipe' => false, 'veredito' => 'ok',
                                'testes' => [{ 'pedido' => 1, 'veredito' => 'ok' }] }] }
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(self).to receive(:cliente_do_eval).and_return(cliente)
    allow(cliente).to receive(:create).and_return(text: { perguntas_mostram_a_mudanca: true, alguma_cita_instrucao: false,
                                                          vereditos_certos: [true], justificativa: 'ok' }.to_json)

    prova['perguntas'].first['trechos'] = ['Aulas às 19h.']
    linha_nova = linha(caso, true, prova, %w[curto preço], julgar(caso, prova, %w[curto preço], 'tone' => 'formal depois'))

    expect(linha_nova).to include(aprovada: true, pedidos_aplicados: %w[curto preço])
    expect(cliente).to have_received(:create) do |**kwargs|
      expect(kwargs[:instructions]).to include(Autonomia::Agents::JuizDaProva::INSTRUCAO)
      texto = kwargs[:input].first[:content].first[:text]
      expect(texto).to include('"pedido": "preço"', '{"tone":"formal depois"}', '"trechos_da_base_usados": [', 'Aulas às 19h.')
    end
  end

  # Revisão do t6d (BAIXOS do rejulgar): o arquivo gravado, lido de verdade.
  describe 'rejulgar um relatório gravado, com o juiz do eval dublado' do
    let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
    let(:caso) { AvaliacaoDaProvaDoAjuste::CASOS.first }
    let(:pronta) do
      { 'caso' => caso[:nome], 'applied' => true, 'pedidos_aplicados' => %w[curto], 'agente_do_juiz' => { 'tone' => 'formal depois' },
        'prova' => { 'status' => 'pronta', 'total' => 1, 'ok' => 1, 'completa' => true,
                     'perguntas' => [{ 'pergunta' => 'Oi', 'resposta' => 'Olá.', 'equipe' => false, 'veredito' => 'ok',
                                       'testes' => [{ 'pedido' => 0, 'veredito' => 'ok' }] }] } }
    end

    before do
      allow(self).to receive(:cliente_do_eval).and_return(cliente)
      allow(cliente).to receive(:create).and_return(text: { perguntas_mostram_a_mudanca: true, alguma_cita_instrucao: false,
                                                            vereditos_certos: [true], justificativa: 'ok' }.to_json)
    end

    def arquivo_com(execucoes)
      Tempfile.new(%w[relatorio .json]).tap do |arquivo|
        arquivo.write(JSON.generate(execucoes: execucoes))
        arquivo.flush
      end
    end

    it 'julga só a prova pronta, com o retrato gravado, pula a não pronta sem chamar o juiz e ignora controle' do
      nao_pronta = pronta.merge('caso' => AvaliacaoDaProvaDoAjuste::CASOS.second[:nome], 'prova' => { 'status' => 'erro' })
      controle = { 'caso' => 'controle_emoji', 'controle' => true }

      rejulgar_arquivo(arquivo_com([pronta, nao_pronta, controle]).path)

      expect(relatorio.pluck(:caso)).to eq([caso[:nome], AvaliacaoDaProvaDoAjuste::CASOS.second[:nome]])
      expect(relatorio.pluck(:aprovada)).to eq([true, false])
      expect(cliente).to have_received(:create).once.with(hash_including(input: [hash_including(
        content: [hash_including(text: a_string_including('{"tone":"formal depois"}'))]
      )]))
    end

    it 'falha com caso desconhecido no relatório, antes de chamar o juiz' do
      expect { rejulgar_arquivo(arquivo_com([pronta.merge('caso' => 'caso_que_nao_existe')]).path) }
        .to raise_error(ArgumentError, /caso_que_nao_existe/)
      expect(cliente).not_to have_received(:create)
    end
  end

  # Forense do t6d (M4): o mesmo relatório julgado de novo, só pelo juiz do eval (para medir a régua sem pagar o resto).
  it 'rejulga um relatório gravado chamando só o juiz do eval' do
    arquivo = ENV.fetch('PROVA_DO_AJUSTE_EVAL_REJULGAR', '')
    skip 'rejulgar: rode com PROVA_DO_AJUSTE_EVAL_REJULGAR=<relatorio.json> e a avaliação paga ligada' unless ligada? && arquivo.present?

    ligar_a_chave!
    gravadas = rejulgar_arquivo(arquivo)

    gravar_relatorio
    expect(relatorio.size).to eq(gravadas), "teto de custo atingido: #{relatorio.size} de #{gravadas}"
  end

  # -> quantos casos o relatório tem. Caso que o eval não conhece falha antes de qualquer chamada; prova que não ficou
  # pronta entra reprovada, sem chamar o juiz.
  def rejulgar_arquivo(arquivo)
    gravadas = JSON.parse(File.read(arquivo))['execucoes'].reject { |gravada| gravada['controle'] }
    casos = AvaliacaoDaProvaDoAjuste::CASOS.index_by { |caso| caso[:nome] }
    desconhecidos = gravadas.pluck('caso') - casos.keys
    raise ArgumentError, "caso desconhecido no relatório: #{desconhecidos.join(', ')}" if desconhecidos.any?

    gravadas.each do |gravada|
      break if custo_ate_agora >= teto

      relatorio << rejulgar(casos.fetch(gravada['caso']), gravada)
    end
    gravadas.size
  end

  def rejulgar(caso, gravada)
    prova = gravada['prova'].to_h
    pedidos = Array(gravada['pedidos_aplicados'])
    veredito = prova['status'] == 'pronta' ? julgar(caso, prova, pedidos, gravada['agente_do_juiz']) : {}
    linha(caso, gravada['applied'], prova, pedidos, veredito)
  end
end
