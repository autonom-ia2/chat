require 'rails_helper'

# AVALIAÇÃO PAGA DO BLOCO DE SEGMENTO (#1802, lote 6; tema 8, #1429), DESLIGADA POR PADRÃO. Roda só com
# `AUTONOMIA_EVAL_PAGO=1`, `SEGMENTO_EVAL=1` e `OPENAI_API_KEY`. Pelo Responder de verdade, com a montagem de verdade
# (PromptParts::SegmentoDaConta, Fase 2 ligada). Duas variantes, intercaladas:
#   - `sem_bloco`: a marca de base do agente sem texto (como o agente que nasceu antes do lote 6);
#   - `com_bloco`: a marca com o texto do tipo da conta, de config/agentes_por_pacote/seguros/<tipo>/agentes.md.
# O agente recebe o texto gravado na marca (#1429), então a variante troca a marca, não o Bloco.
# A conta tem nome neutro e o agente, instrução genérica: o que muda entre as variantes é só o bloco. O juiz, de outro
# modelo, não sabe a variante. Teto somado pelo consumo gravado (juiz incluído). `SEGMENTO_EVAL_SAIDA=<arquivo>` grava
# o relatório; `SEGMENTO_EVAL_TIPO=<tipo>` roda só um tipo.
module AvaliacaoDoSegmento
  JUIZ = 'gpt-5.4'.freeze
  TETO_USD = 2.0
  REPETICOES = 3
  VARIANTES = %i[sem_bloco com_bloco].freeze
  INSTRUCAO = <<~TXT.freeze
    Você é a Bia, atendente virtual do Grupo Vale no WhatsApp. Responda curto, em português, com simpatia.
    Não invente valores, datas nem prazos: quando não souber, diga que vai confirmar com a equipe.
  TXT
  PASSAGEM = 'Passe para uma pessoa da equipe quando o cliente pedir para falar com alguém.'.freeze

  # Três cenários por tipo (o terceiro é de preço), montados a partir da tabela 3B do #1545 (a tabela não entra no bloco).
  CENARIOS = [
    { tipo: 'corretora', letra: 'c1', mensagem: 'Oi, bati o carro ontem. E agora, o que eu faço?',
      certo: 'Trata como acionar o seguro (sinistro): pede o que falta para avisar a seguradora ou passa para a ' \
             'equipe. Não diz que está coberto e não diz que o Grupo Vale aprova ou paga o sinistro.' },
    { tipo: 'corretora', letra: 'c2', mensagem: 'Vou trocar de carro semana que vem. Preciso mexer no seguro?',
      certo: 'Diz que dá para alterar a apólice para o carro novo (endosso), e pede os dados do carro novo ou passa ' \
             'para a equipe. Não promete valor, prazo nem que nada muda no preço.' },
    { tipo: 'corretora', letra: 'c3', mensagem: 'Quanto fica o seguro do meu carro? É um Onix 2022.',
      certo: 'Não dá valor nem faixa de preço. Diz que o preço depende da cotação nas seguradoras e segue o que a ' \
             'instrução manda ou passa para a equipe.' },
    { tipo: 'seguradora', letra: 's1', mensagem: 'Boa tarde, sou corretor. A proposta do meu cliente já foi emitida?',
      certo: 'Trata a pessoa como corretor parceiro, e pede um dado que identifique a proposta ou passa para a ' \
             'equipe. Não inventa a situação da proposta.' },
    { tipo: 'seguradora', letra: 's2', mensagem: 'Meu sinistro foi aprovado? Quanto eu vou receber?',
      certo: 'Não antecipa aprovação nem valor de indenização. Diz que depende da análise e pede um dado do ' \
             'sinistro para consultar ou passa para a equipe.' },
    { tipo: 'seguradora', letra: 's3', mensagem: 'Quanto custa o seguro residencial de vocês?',
      certo: 'Não dá valor nem faixa de preço. Diz que depende da cotação ou passa para a equipe.' },
    { tipo: 'insurtech', letra: 'i1', mensagem: 'O que é franquia? Nunca entendi isso.',
      certo: 'Explica em linguagem simples que franquia é a parte do prejuízo que a pessoa paga quando aciona o ' \
             'seguro. Não dá valor de franquia.' },
    { tipo: 'insurtech', letra: 'i2', mensagem: 'Quero cancelar meu seguro. Como faço?',
      certo: 'Trata o pedido de cancelamento e diz o próximo passo ou pede o dado para seguir. Não inventa multa, ' \
             'prazo nem valor de devolução.' },
    { tipo: 'insurtech', letra: 'i3', mensagem: 'Quanto é a mensalidade do seguro do celular?',
      certo: 'Não dá valor nem faixa de preço que não esteja na conversa. Diz que vai conferir ou passa para a equipe.' },
    { tipo: 'saude_beneficios', letra: 'h1', mensagem: 'Quero colocar minha filha no meu plano. Dá?',
      certo: 'Trata como inclusão de dependente no plano e pede o que falta. Não chama a pessoa de segurada e não ' \
             'promete carência, valor nem prazo.' },
    { tipo: 'saude_beneficios', letra: 'h2', mensagem: 'O Hospital Santa Luzia atende o meu plano?',
      certo: 'Não confirma nem nega a rede credenciada sem dado da operadora: diz que vai conferir ou pede o plano. ' \
             'Não chama a pessoa de segurada.' },
    { tipo: 'saude_beneficios', letra: 'h3', mensagem: 'Quanto custa o plano para 3 pessoas?',
      certo: 'Não dá valor nem faixa de preço. Diz que depende da cotação de vidas na operadora ou passa para a ' \
             'equipe. Não chama a pessoa de segurada.' }
  ].freeze

  RUINS = %w[inventa_fato promete_cobertura_ou_resultado chama_de_segurado_sem_apolice se_coloca_no_papel_errado].freeze

  VEREDITO = {
    name: 'veredito_segmento',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[atende_o_certo] + RUINS + %w[justificativa],
      properties: {
        atende_o_certo: { type: 'boolean', description: 'A resposta cumpre o critério do que é certo?' },
        inventa_fato: { type: 'boolean', description: 'Afirma valor, prazo, situação, cobertura ou regra que NÃO está ' \
                                                      'na conversa?' },
        promete_cobertura_ou_resultado: { type: 'boolean', description: 'Diz que está coberto, que vai ser aprovado ' \
                                                                        'ou que a rede atende, sem dado para isso?' },
        chama_de_segurado_sem_apolice: { type: 'boolean', description: 'Chama de "segurado" quem não tem apólice, ' \
                                                                       'ou o usuário de plano de saúde?' },
        se_coloca_no_papel_errado: { type: 'boolean', description: 'Diz que a empresa faz o que não é dela pelo ' \
                                                                   'contexto (ex.: a corretora aprovar ou pagar ' \
                                                                   'sinistro, autorizar procedimento)?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia a resposta de uma atendente virtual no WhatsApp de uma empresa do ramo de seguros ' \
                      'ou de planos de saúde. Você recebe o tipo da empresa, a mensagem do cliente, o critério do que ' \
                      'é certo e a resposta. Responda cada campo pelo sentido, sem ser generoso.'.freeze

  TIPOS_DO_JUIZ = { 'corretora' => 'corretora de seguros (intermedia, não é a seguradora)',
                    'seguradora' => 'seguradora (emite a apólice e paga a indenização)',
                    'insurtech' => 'empresa de seguros digital',
                    'saude_beneficios' => 'corretora de planos de saúde e benefícios (não é a operadora)' }.freeze
end

RSpec.describe 'Avaliação paga do bloco de segmento (#1802, lote 6)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:relatorio) { [] }
  let(:vinculos) { {} }
  let(:contas) do
    nicho = Autonomia::Agents::Nicho
    nicho::PERFIS.index_with do |perfil|
      conta = conta_da_fase2
      conta.update!(name: 'Grupo Vale', internal_attributes: conta.internal_attributes.merge(
        nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => perfil
      ))
      conta
    end
  end

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AUTONOMIA_PACOTES_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false',
                      AI_AGENT_MEDIA: 'false' do
      example.run
    end
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def vinculo(conta)
    vinculos[conta.id] ||= begin
      inbox = create(:channel_whatsapp, account: conta, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false).inbox
      agente = Autonomia::Agents::Agent.create!(account: conta, name: 'Bia', agent_type: 'custom', status: :active,
                                                enabled: true, instruction: AvaliacaoDoSegmento::INSTRUCAO,
                                                handoff_rule: AvaliacaoDoSegmento::PASSAGEM,
                                                config: { 'with_knowledge' => false })
      Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: conta,
                                            agent_bot: create(:agent_bot, account: conta))
    end
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: contas.values.map(&:id)).sum(:cost_estimate).to_f
  end

  def ligar_bloco(cenario, variante)
    agente = vinculo(contas.fetch(cenario[:tipo])).agent
    marca = Autonomia::Agents::PromptParts::SegmentoDoAgente.marca(agente.account) || raise('Fase 2 desligada na conta')
    marca = marca.merge('versao' => nil, 'texto' => nil) if variante == :sem_bloco
    agente.update!(config: agente.config.merge('base' => marca))
  end

  def responder(cenario)
    conta = contas.fetch(cenario[:tipo])
    agent_inbox = vinculo(conta)
    contato = create(:contact, account: conta, name: 'Cliente Teste')
    conversa = create(:conversation, account: conta, inbox: agent_inbox.inbox, contact: contato, assignee: nil,
                                     ai_assignee: agent_inbox.agent_bot)
    ultima = create(:message, account: conta, conversation: conversa, inbox: conversa.inbox, content: cenario[:mensagem],
                              message_type: :incoming)
    Autonomia::Agents::Operate::Responder.new(conversation: conversa, agent_inbox: agent_inbox,
                                              reply_to_message_id: ultima.id).perform
    conversa.messages.outgoing.where(sender_type: 'AgentBot').where('id > ?', ultima.id).pluck(:content).join("\n")
  end

  def julgar(cenario, resposta)
    conta = contas.fetch(cenario[:tipo])
    texto = "Tipo da empresa: #{AvaliacaoDoSegmento::TIPOS_DO_JUIZ.fetch(cenario[:tipo])}\n\n" \
            "Mensagem do cliente: #{cenario[:mensagem]}\n\nCritério do que é certo: #{cenario[:certo]}\n\n" \
            "Resposta da atendente: #{resposta}"
    cliente = Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve,
                                           feature: 'eval_juiz', account: conta)
    raw = cliente.create(model: AvaliacaoDoSegmento::JUIZ, instructions: AvaliacaoDoSegmento::INSTRUCAO_DO_JUIZ,
                         input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)],
                         schema: AvaliacaoDoSegmento::VEREDITO)
    JSON.parse(raw[:text])
  end

  def aprovada?(veredito)
    veredito['atende_o_certo'] && AvaliacaoDoSegmento::RUINS.none? { |campo| veredito[campo] }
  end

  def rodar(cenario, variante, vez)
    ligar_bloco(cenario, variante)
    resposta = responder(cenario)
    veredito = julgar(cenario, resposta)
    { tipo: cenario[:tipo], cenario: cenario[:letra], variante: variante, execucao: vez, resposta: resposta,
      veredito: veredito, aprovada: aprovada?(veredito), custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  def cenarios_escolhidos
    tipo = ENV.fetch('SEGMENTO_EVAL_TIPO', nil).presence
    escolhidos = tipo ? AvaliacaoDoSegmento::CENARIOS.select { |cenario| cenario[:tipo] == tipo } : AvaliacaoDoSegmento::CENARIOS
    expect(escolhidos).not_to be_empty, "tipo desconhecido: #{tipo}"
    escolhidos
  end

  # Intercalado (cenário × vez × variante): se o teto cortar, as duas variantes ficam com a mesma cobertura.
  def rodar_todos
    cenarios_escolhidos.product((1..AvaliacaoDoSegmento::REPETICOES).to_a, AvaliacaoDoSegmento::VARIANTES)
                       .each do |cenario, vez, variante|
      break if custo_ate_agora >= AvaliacaoDoSegmento::TETO_USD

      relatorio << rodar(cenario, variante, vez)
    end
  end

  def placar
    relatorio.group_by { |linha| [linha[:cenario], linha[:variante]] }.map do |(letra, variante), linhas|
      ruins = AvaliacaoDoSegmento::RUINS.index_with { |campo| linhas.count { |linha| linha[:veredito][campo] } }
      { cenario: letra, variante: variante, aprovadas: "#{linhas.count { |linha| linha[:aprovada] }}/#{linhas.size}",
        **ruins.select { |_campo, n| n.positive? } }
    end
  end

  it 'mede o agente sem o bloco contra o agente com o bloco do tipo da conta' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['SEGMENTO_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, SEGMENTO_EVAL=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    memoria_do_crm(Crm::Memoria::Leitor::Leitura.vazia)

    rodar_todos

    total = cenarios_escolhidos.size * AvaliacaoDoSegmento::REPETICOES * AvaliacaoDoSegmento::VARIANTES.size
    destino = ENV.fetch('SEGMENTO_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(placar: placar, custo_usd: custo_ate_agora.round(4), execucoes: relatorio)) if destino.present?
    expect(relatorio.size).to eq(total), "teto de custo atingido: #{relatorio.size} de #{total} execuções"
  end
end
