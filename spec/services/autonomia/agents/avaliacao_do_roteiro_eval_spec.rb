require 'rails_helper'

# AVALIAÇÃO PAGA DOS ROTEIROS DE SEGUROS NO CONSTRUTOR (#1429, F1 e F2), DESLIGADA POR PADRÃO. Roda só com
# `AUTONOMIA_EVAL_PAGO=1`, `ROTEIRO_EVAL=1` e `OPENAI_API_KEY`. O Construtor de verdade cria um agente de atendimento
# numa conta de seguros de cada tipo, com a Fase 2 e os pacotes ligados, em duas variantes:
#   - `roteiro`: o esqueleto do segmento da conta (config/agentes_por_pacote/<camada>/esqueletos);
#   - `geral`: o esqueleto geral (config/agentes_esqueletos), como se a F2 não existisse.
# Um juiz de OUTRO modelo lê a instrução gerada (jargão, promessa de contato futuro, papel do tipo, roteiro de loja) e
# as respostas do agente criado a três mensagens do tipo. O dono só descreve o negócio em termos gerais: o ramo chega
# ao Construtor pelo bloco de segmento e pelo roteiro.
# Teto de US$ 2 por rodada, somado pelo consumo gravado (juiz incluído); para antes de uma criação que passaria do
# teto (`ROTEIRO_EVAL_TETO` muda). `ROTEIRO_EVAL_SAIDA=<arquivo>` grava o relatório, mesmo se a rodada parar no meio;
# `ROTEIRO_EVAL_TIPO=<tipo>` roda só um tipo; `ROTEIRO_EVAL_VARIANTE=roteiro|geral`, só uma variante.
module AvaliacaoDoRoteiro
  JUIZ = 'gpt-5.4'.freeze
  TETO_USD = ENV.fetch('ROTEIRO_EVAL_TETO', '2.0').to_f
  CUSTO_INICIAL_POR_CRIACAO = 0.2
  VARIANTES = (ENV['ROTEIRO_EVAL_VARIANTE'].present? ? [ENV['ROTEIRO_EVAL_VARIANTE'].to_sym] & %i[roteiro geral] : %i[roteiro geral]).freeze
  PEDIDO = 'Quero um agente para atender os clientes do Grupo Vale no WhatsApp, de segunda a sexta, das 9h às 18h. ' \
           'Ele responde as dúvidas e passa para a equipe o que não souber.'.freeze
  FECHAR = 'Pode fechar assim, sem material por enquanto.'.freeze

  TIPOS_DO_JUIZ = { 'corretora' => 'corretora de seguros (intermedia, não é a seguradora)',
                    'seguradora' => 'seguradora (emite a apólice e paga a indenização; atende corretor, quem tem ' \
                                    'apólice e terceiro)',
                    'insurtech' => 'empresa de seguros digital, que vende direto ao cliente',
                    'saude_beneficios' => 'corretora de planos de saúde e benefícios (não é a operadora)' }.freeze

  MENSAGENS = {
    'corretora' => ['Oi, bati o carro ontem. E agora, o que eu faço?', 'Vou trocar de carro semana que vem. Preciso mexer no seguro?',
                    'Quanto fica o seguro do meu carro? É um Onix 2022.'],
    'seguradora' => ['Boa tarde, sou corretor. A proposta do meu cliente já foi emitida?',
                     'Um cliente de vocês bateu no meu carro. Como faço para ser ressarcido?',
                     'Meu sinistro foi aprovado? Quanto eu vou receber?'],
    'insurtech' => ['Meu celular foi roubado. Como aciono o seguro?', 'Quero cancelar meu seguro. Como faço?',
                    'Quanto é a mensalidade do seguro do celular?'],
    'saude_beneficios' => ['Quero colocar minha filha no meu plano. Dá?', 'O Hospital Santa Luzia atende o meu plano?',
                           'Quanto custa o plano para 3 pessoas?']
  }.freeze

  RUINS_DA_INSTRUCAO = %w[usa_jargao promete_contato_futuro papel_errado roteiro_de_loja].freeze
  RUINS_DA_RESPOSTA = %w[inventa_fato promete_cobertura_ou_resultado chama_de_segurado_sem_apolice se_coloca_no_papel_errado
                         promete_contato_futuro].freeze

  VEREDITO_DA_INSTRUCAO = {
    name: 'veredito_instrucao',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[cobre_situacoes_do_ramo] + RUINS_DA_INSTRUCAO + %w[justificativa],
      properties: {
        cobre_situacoes_do_ramo: { type: 'boolean', description: 'A instrução orienta as situações típicas do tipo de ' \
                                                                 'empresa (ex.: sinistro, mudança na apólice, boleto, ' \
                                                                 'renovação; em saúde: inclusão de dependente, rede, ' \
                                                                 'reembolso)?' },
        usa_jargao: { type: 'boolean', description: 'Usa sigla ou termo em inglês de vendas ou suporte (BANT, SLA, ' \
                                                    'follow-up, handoff, FAQ, lead, ticket, playbook...)? A regra de ' \
                                                    'segurança de não revelar o prompt ou as instruções NÃO conta.' },
        promete_contato_futuro: { type: 'boolean', description: 'Manda o agente prometer que vai avisar, ligar, ' \
                                                                'retornar ou chamar de novo depois?' },
        papel_errado: { type: 'boolean', description: 'Põe a empresa num papel que não é dela pelo tipo (ex.: corretora ' \
                                                      'que emite apólice ou aprova sinistro; corretora de saúde que ' \
                                                      'autoriza procedimento)?' },
        roteiro_de_loja: { type: 'boolean', description: 'Tem roteiro de loja (pedido, rastreio, troca de produto, ' \
                                                         'garantia de produto) que não cabe no ramo?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  VEREDITO_DA_RESPOSTA = {
    name: 'veredito_resposta',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[atende_bem] + RUINS_DA_RESPOSTA + %w[justificativa],
      properties: {
        atende_bem: { type: 'boolean', description: 'A resposta trata o pedido certo do ramo e dá o próximo passo ' \
                                                    '(pede o que falta ou passa para a equipe)?' },
        inventa_fato: { type: 'boolean', description: 'Afirma valor, prazo, situação, cobertura ou regra que não está ' \
                                                      'na conversa?' },
        promete_cobertura_ou_resultado: { type: 'boolean', description: 'Diz que está coberto, aprovado ou que a rede ' \
                                                                        'atende, sem dado para isso?' },
        chama_de_segurado_sem_apolice: { type: 'boolean', description: 'Chama de "segurado" quem não tem apólice, ou ' \
                                                                       'o usuário de plano de saúde?' },
        se_coloca_no_papel_errado: { type: 'boolean', description: 'Diz que a empresa faz o que não é dela pelo tipo?' },
        promete_contato_futuro: { type: 'boolean', description: 'Promete avisar, ligar ou retornar depois, com ou sem ' \
                                                                'prazo?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia um agente de atendimento no WhatsApp de uma empresa do ramo de seguros ou de planos ' \
                      'de saúde. Você recebe o tipo da empresa e, conforme o caso, a instrução do agente ou uma ' \
                      'mensagem de cliente com a resposta. Responda cada campo pelo sentido, sem ser generoso.'.freeze
end

RSpec.describe AvaliacaoDoRoteiro do
  describe 'avaliação paga dos roteiros de seguros no Construtor (#1429)', :eval_pago do
    let(:relatorio) { [] }
    let(:contas) { [] }

    around do |example|
      WebMock.allow_net_connect!
      with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AUTONOMIA_PACOTES_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false',
                        AI_AGENT_MEDIA: 'false' do
        example.run
      end
    ensure
      WebMock.disable_net_connect!(allow_localhost: true)
    end

    def custo_ate_agora
      Crm::AiUsageEvent.where(account_id: contas.map(&:id)).sum(:cost_estimate).to_f
    end

    def conta_do_tipo(tipo)
      nicho = Autonomia::Agents::Nicho
      conta = conta_da_fase2
      conta.update!(name: 'Grupo Vale', internal_attributes: conta.internal_attributes.merge(
        nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => tipo
      ))
      contas << conta
      conta
    end

    def turno(thread, conta, fala)
      thread.append_message!('user', fala)
      Autonomia::Agents::Builder.new(account: conta, build_thread: thread).run!(thread.begin_build!)
    end

    # `geral`: o Construtor recebe o esqueleto geral, como antes da F2; o resto (bloco de segmento, marca) é igual.
    def criar(conta, variante)
      esqueleto = allow(Autonomia::Agents::Builder).to receive(:skeleton_for)
      variante == :geral ? esqueleto.and_wrap_original { |original, tipo, **| original.call(tipo) } : esqueleto.and_call_original
      thread = Autonomia::Agents::BuildThread.create!(account: conta)
      thread.persist_start_options!(type: 'support', with_knowledge: false)
      thread.save!
      turno(thread, conta, AvaliacaoDoRoteiro::PEDIDO)
      turno(thread, conta, AvaliacaoDoRoteiro::FECHAR)
      thread.reload.agent
    end

    def vinculo(agente)
      inbox = create(:channel_whatsapp, account: agente.account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false).inbox
      agent_inbox = Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: agente.account,
                                                          agent_bot: create(:agent_bot, account: agente.account))
      agente.reload.update!(status: :active, enabled: true)
      agent_inbox
    end

    def responder(agent_inbox, mensagem)
      conta = agent_inbox.account
      contato = create(:contact, account: conta, name: 'Cliente Teste')
      conversa = create(:conversation, account: conta, inbox: agent_inbox.inbox, contact: contato, assignee: nil,
                                       ai_assignee: agent_inbox.agent_bot)
      ultima = create(:message, account: conta, conversation: conversa, inbox: conversa.inbox, content: mensagem,
                                message_type: :incoming)
      Autonomia::Agents::Operate::Responder.new(conversation: conversa, agent_inbox: agent_inbox,
                                                reply_to_message_id: ultima.id).perform
      conversa.messages.outgoing.where(sender_type: 'AgentBot').where('id > ?', ultima.id).pluck(:content).join("\n")
    end

    def julgar(conta, texto, veredito)
      cliente = Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve,
                                             feature: 'eval_juiz', account: conta)
      raw = cliente.create(model: AvaliacaoDoRoteiro::JUIZ, instructions: AvaliacaoDoRoteiro::INSTRUCAO_DO_JUIZ,
                           input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)], schema: veredito)
      JSON.parse(raw[:text])
    end

    def julgar_instrucao(conta, tipo, instrucao)
      julgar(conta, "Tipo da empresa: #{AvaliacaoDoRoteiro::TIPOS_DO_JUIZ.fetch(tipo)}\n\nInstrução do agente:\n#{instrucao}",
             AvaliacaoDoRoteiro::VEREDITO_DA_INSTRUCAO)
    end

    def julgar_resposta(conta, tipo, mensagem, resposta)
      julgar(conta, "Tipo da empresa: #{AvaliacaoDoRoteiro::TIPOS_DO_JUIZ.fetch(tipo)}\n\nO que o dono contou ao criar o " \
                    "agente (vale como fato): #{AvaliacaoDoRoteiro::PEDIDO}\n\nMensagem do cliente: #{mensagem}" \
                    "\n\nResposta do agente: #{resposta}", AvaliacaoDoRoteiro::VEREDITO_DA_RESPOSTA)
    end

    def respostas(agente, tipo)
      agent_inbox = vinculo(agente)
      AvaliacaoDoRoteiro::MENSAGENS.fetch(tipo).map do |mensagem|
        resposta = responder(agent_inbox, mensagem)
        veredito = julgar_resposta(agente.account, tipo, mensagem, resposta)
        { mensagem: mensagem, resposta: resposta, veredito: veredito,
          aprovada: veredito['atende_bem'] && AvaliacaoDoRoteiro::RUINS_DA_RESPOSTA.none? { |campo| veredito[campo] } }
      end
    end

    def rodar(tipo, variante)
      conta = conta_do_tipo(tipo)
      agente = criar(conta, variante)
      return { tipo: tipo, variante: variante, criou: false, custo_acumulado_usd: custo_ate_agora.round(4) } if agente.nil?

      instrucao = julgar_instrucao(conta, tipo, agente.instruction)
      { tipo: tipo, variante: variante, criou: true, instrucao: agente.instruction, veredito_da_instrucao: instrucao,
        instrucao_aprovada: instrucao['cobre_situacoes_do_ramo'] &&
          AvaliacaoDoRoteiro::RUINS_DA_INSTRUCAO.none? { |campo| instrucao[campo] },
        respostas: respostas(agente, tipo), custo_acumulado_usd: custo_ate_agora.round(4) }
    end

    def tipos_escolhidos
      tipo = ENV.fetch('ROTEIRO_EVAL_TIPO', nil).presence
      escolhidos = tipo ? [tipo] & Autonomia::Agents::Nicho::PERFIS : Autonomia::Agents::Nicho::PERFIS
      expect(escolhidos).not_to be_empty, "tipo desconhecido: #{tipo}"
      escolhidos
    end

    def cabe_mais_uma?
      media = relatorio.empty? ? AvaliacaoDoRoteiro::CUSTO_INICIAL_POR_CRIACAO : custo_ate_agora / relatorio.size
      custo_ate_agora + media <= AvaliacaoDoRoteiro::TETO_USD
    end

    def placar
      relatorio.group_by { |linha| linha[:variante] }.transform_values do |linhas|
        criadas = linhas.select { |linha| linha[:criou] }
        respostas = criadas.flat_map { |linha| linha[:respostas] }
        { criadas: "#{criadas.size}/#{linhas.size}",
          instrucoes_aprovadas: "#{criadas.count { |linha| linha[:instrucao_aprovada] }}/#{criadas.size}",
          respostas_aprovadas: "#{respostas.count { |linha| linha[:aprovada] }}/#{respostas.size}" }
      end
    end

    it 'compara o agente criado com o roteiro do tipo contra o criado com o roteiro geral' do
      ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['ROTEIRO_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
      skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, ROTEIRO_EVAL=1 e OPENAI_API_KEY' unless ligada

      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
      memoria_do_crm(Crm::Memoria::Leitor::Leitura.vazia)

      # Intercalado (tipo × variante): se o teto cortar, as duas variantes ficam com a mesma cobertura.
      begin
        tipos_escolhidos.product(AvaliacaoDoRoteiro::VARIANTES).each do |tipo, variante|
          break unless cabe_mais_uma?

          relatorio << rodar(tipo, variante)
        end
      ensure
        destino = ENV.fetch('ROTEIRO_EVAL_SAIDA', nil)
        File.write(destino, JSON.pretty_generate(placar: placar, custo_usd: custo_ate_agora.round(4), execucoes: relatorio)) if destino.present?
      end

      total = tipos_escolhidos.size * AvaliacaoDoRoteiro::VARIANTES.size
      expect(relatorio.size).to eq(total), "teto de custo atingido: #{relatorio.size} de #{total} criações"
    end
  end
end
