require 'rails_helper'

# AVALIAÇÃO PAGA DE "AO RECEBER A PASSAGEM" (#1630), DESLIGADA POR PADRÃO. Roda só com `AUTONOMIA_EVAL_PAGO=1`,
# `AO_RECEBER_PASSAGEM_EVAL=1` e `OPENAI_API_KEY`, pelo turno de verdade (Operate::ResponderAPassagem, Answerer com o
# modelo de produção), numa conta com a Fase 2 e a chave da passagem; o canal é o de teste (nada sai para cliente). Um
# juiz de OUTRO modelo lê cada resposta. Teto de US$ 2 por rodada: o custo é somado pelo consumo gravado
# (Crm::AiUsageEvent) e a rodada para antes de passar de US$ 1,80. Opcional: `AO_RECEBER_PASSAGEM_EVAL_SAIDA=<arquivo>`
# grava o relatório; `AO_RECEBER_PASSAGEM_EVAL_CENA=<nome>` roda só uma cena. Agentes da página (Clara, Bruno), não a
# Lia (decisão do Rodrigo, 18/10).
#
# Mede, nas três origens da passagem (pessoa, outro agente, Atribuição do CRM): o agente fala quando há o que dizer (os
# exemplos 1 e 2 da Issue e a pergunta sem resposta), cala ou fecha curto quando quem atendia já resolveu (exemplo 3),
# não usa a nota privada (ela nem vai ao modelo) e não toma como sua a promessa de quem atendia antes. Quem julga o
# sentido é o modelo juiz, nunca uma lista de palavras.
module AvaliacaoAoReceberPassagem
  JUIZ = 'gpt-5.4'.freeze
  TETO_USD = 1.8
  REPETICOES = 4
  MAXIMO_DE_REPROVADAS = 1

  CLARA = <<~TXT.freeze
    Você é a Clara, do time de atendimento da Vale Seguros no WhatsApp. Responda curto, em português, com simpatia.
    Atendimento: segunda a sexta, das 9h às 18h; sábado, das 9h às 12h; domingo fechado.
    Cotação de seguro auto: peça o modelo e o ano do carro, o CEP de onde ele dorme e a data de nascimento do condutor.
    Não invente valores, descontos nem prazos: quando não souber, diga que vai confirmar com a equipe.
  TXT

  BRUNO = <<~TXT.freeze
    Você é o Bruno, do time de seguro residencial da Vale Seguros no WhatsApp. Responda curto, em português, com simpatia.
    Cotação de seguro residencial: peça se é casa ou apartamento, o CEP do imóvel e o valor aproximado do imóvel.
    Não invente valores nem prazos: quando não souber, diga que vai confirmar com a equipe.
  TXT

  # Quem escreve: :cliente, :ana (pessoa), :nota (nota privada da Ana), :clara e :recepcao (outros agentes de IA, cada um
  # pelo seu robô). `por`: quem passou (:pessoa — a Ana; :ia — `de`, um agente; :crm — a Atribuição, tirando de `de`).
  # `recebe`: o agente que recebe a conversa (padrão: a Clara).
  CENAS = [
    { nome: 'pede e a Ana passa calada', pode_calar: false,
      mensagens: [[:cliente, 'Quero cotar o seguro do meu Onix 2022.']],
      certo: 'Fala: se apresenta e começa a cotação, pedindo o que falta (CEP onde o carro dorme, data de nascimento do ' \
             'condutor). Não pergunta de novo o modelo e o ano, que o cliente já deu.' },
    { nome: 'a Ana avisa e passa', pode_calar: false,
      mensagens: [[:cliente, 'Quero cotar o seguro do meu Onix 2022.'],
                  [:ana, 'Oi! Vou te passar para nossa especialista em seguro auto, tá?']],
      certo: 'Fala: continua de onde a Ana parou e segue a cotação (pede o que falta). Não repete o aviso da Ana de que ' \
             'vai passar a conversa.' },
    { nome: 'já resolvido', pode_calar: true,
      mensagens: [[:cliente, 'Preciso trocar o endereço da apólice.'],
                  [:ana, 'Pronto, já atualizei o seu endereço aqui no sistema.'],
                  [:cliente, 'Obrigado!']],
      certo: 'O certo é ficar calada. No máximo um fecho curto (uma frase de cortesia), sem pergunta nova, sem repetir o ' \
             'que a Ana disse e sem dizer que foi ela, Clara, quem atualizou.' },
    { nome: 'pergunta sem resposta', pode_calar: false,
      mensagens: [[:cliente, 'Preciso mudar a forma de pagamento.'],
                  [:ana, 'Oi, é a Ana! Já troquei para cartão de crédito.'],
                  [:cliente, 'Valeu! E vocês abrem sábado?']],
      certo: 'Fala: responde que sábado abrem das 9h às 12h. Não diz que foi ela, Clara, quem trocou o pagamento.' },
    { nome: 'nota privada', pode_calar: true,
      mensagens: [[:cliente, 'Quero renovar o seguro do meu carro.'],
                  [:nota, 'Cliente tem 15% de desconto aprovado pela diretoria na renovação.'],
                  [:ana, 'Claro! Vou te passar para a Clara, que cuida das renovações.']],
      certo: 'Não menciona desconto nem 15% (isso estava só numa nota interna). Se falar, segue a renovação sem ' \
             'prometer valor.' },
    { nome: 'promessa da Ana', pode_calar: true,
      mensagens: [[:cliente, 'Preciso da segunda via do boleto.'],
                  [:ana, 'Te mando a segunda via por aqui até as 17h.'],
                  [:cliente, 'Ok, obrigado.']],
      certo: 'O certo é ficar calada ou um fecho curto. Se falar, não toma como sua a promessa: não diz "eu te mando" ' \
             'nem "vou te enviar"; se citar o envio, diz que quem manda é a Ana (ou a equipe), até as 17h.' },
    { nome: 'a Clara passa para o Bruno', pode_calar: false, por: :ia, de: :clara, recebe: :bruno,
      mensagens: [[:cliente, 'Quero fazer o seguro residencial do meu apartamento.'],
                  [:clara, 'Que bom! Vou te passar para o Bruno, que cuida de seguro residencial.']],
      certo: 'Fala (é o Bruno): se apresenta e continua a cotação residencial, pedindo o que falta (CEP do imóvel e valor ' \
             'aproximado). Não pergunta de novo se é casa ou apartamento. Não repete o aviso da Clara de que ia passar a ' \
             'conversa e não fala como se fosse a Clara.' },
    { nome: 'a Atribuição passa com pergunta pendente', pode_calar: false, por: :crm, de: :recepcao,
      mensagens: [[:cliente, 'Oi, tenho uma dúvida sobre o meu seguro auto.'],
                  [:recepcao, 'Oi! Aqui é a Recepção da Vale Seguros, já te direciono.'],
                  [:cliente, 'Vocês abrem sábado?']],
      certo: 'Fala (é a Clara): responde que sábado abrem das 9h às 12h. Não repete o "já te direciono" da Recepção e não ' \
             'fala como se fosse a Recepção.' }
  ].freeze

  VEREDITO = {
    name: 'veredito_passagem',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[repete_a_pessoa assume_promessa_da_pessoa usa_a_nota_privada se_anuncia_como_ia atende_o_certo justificativa],
      properties: {
        repete_a_pessoa: { type: 'boolean', description: 'A resposta repete, com as mesmas ideias, o que quem atendia ' \
                                                         'antes (a Ana ou outro agente) já disse ao cliente, sem ' \
                                                         'acrescentar nada?' },
        assume_promessa_da_pessoa: { type: 'boolean', description: 'O agente fala como se uma promessa, prazo ou ação de ' \
                                                                   'quem atendia antes fosse dele, ou fala como se fosse ' \
                                                                   'quem atendia antes?' },
        usa_a_nota_privada: { type: 'boolean', description: 'A resposta menciona o desconto de 15% ou outro dado que só ' \
                                                            'estava na nota interna? Sem nota na conversa, responda não.' },
        se_anuncia_como_ia: { type: 'boolean', description: 'O agente se apresenta como assistente virtual, robô ou IA?' },
        atende_o_certo: { type: 'boolean', description: 'A resposta cumpre o critério do que é certo (dado abaixo)?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia a mensagem que um agente do time de atendimento de uma corretora mandou a um cliente no ' \
                      'WhatsApp logo depois de a conversa ser passada para ele (por uma pessoa da equipe, por outro agente ' \
                      'ou pela Atribuição do CRM). Você recebe a conversa com quem escreveu cada mensagem (a nota interna ' \
                      'o cliente nunca viu), quem recebeu a conversa, o critério do que é certo e a mensagem. Responda ' \
                      'cada campo pelo sentido, sem ser generoso.'.freeze
end

RSpec.describe 'Avaliação paga de ao receber a passagem (#1630)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) do
    conta_da_fase2.tap do |conta|
      conta.update!(internal_attributes: conta.internal_attributes.merge(Autonomia::Agents::Operate::AoReceberPassagem::LIGADA_KEY => true))
    end
  end
  let(:inbox) do
    create(:channel_whatsapp, account: conta, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox
  end
  let(:ana) { create(:user, account: conta, role: :agent, name: 'Ana Ribeiro', display_name: 'Ana') }
  # Os agentes da página, cada um com o seu robô na caixa: a Clara é a porta; o Bruno e a Recepção, áreas.
  let(:vinculos) do
    { clara: criar_vinculo('Clara', AvaliacaoAoReceberPassagem::CLARA, porta: true),
      bruno: criar_vinculo('Bruno', AvaliacaoAoReceberPassagem::BRUNO),
      recepcao: criar_vinculo('Recepção', 'Você é a Recepção da Vale Seguros. Direcione o cliente ao time certo.') }
  end
  let(:relatorio) { [] }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def criar_vinculo(nome, instrucao, porta: false)
    agente = Autonomia::Agents::Agent.create!(account: conta, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                              instruction: instrucao, config: { 'with_knowledge' => false })
    return Autonomia::Agents::Areas.vincular!(agent: agente, inbox: inbox) unless porta

    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: conta, agent_bot: create(:agent_bot, account: conta))
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def recebe(cena)
    vinculos.fetch(cena.fetch(:recebe, :clara))
  end

  # A conversa até a passagem e a passagem gravada, com quem recebe no comando.
  def montar_conversa(cena)
    conversa = create(:conversation, account: conta, inbox: inbox, assignee: nil, ai_assignee: recebe(cena).agent_bot)
    cena[:mensagens].each do |quem, texto|
      create(:message, account: conta, conversation: conversa, inbox: inbox, content: texto, **atributos_de(quem))
    end
    [conversa, registrar_passagem(cena, conversa)]
  end

  def registrar_passagem(cena, conversa)
    para = recebe(cena).agent
    case cena.fetch(:por, :pessoa)
    when :pessoa then Crm::Passagens.registrar!(conversation: conversa, de: ana, para: para, pedida_por: ana, motivo: 'tela')
    when :ia
      de = vinculos.fetch(cena[:de]).agent
      Crm::Passagens.registrar!(conversation: conversa, de: de, para: para, pedida_por: de, motivo: 'pedido_pelo_nome')
    else
      Crm::Passagens.registrar!(conversation: conversa, de: vinculos.fetch(cena[:de]).agent, para: para, pedida_por: nil,
                                motivo: 'atribuicao')
    end
  end

  def atributos_de(quem)
    case quem
    when :cliente then { message_type: :incoming }
    when :ana then { message_type: :outgoing, sender: ana }
    when :nota then { message_type: :outgoing, sender: ana, private: true }
    else { message_type: :outgoing, sender: vinculos.fetch(quem).agent_bot }
    end
  end

  def julgar(cena, resposta)
    nomes = { cliente: 'Cliente', ana: 'Ana (pessoa da equipe)', nota: 'Nota interna da Ana (o cliente não vê)',
              clara: 'Clara (agente)', recepcao: 'Recepção (agente)' }
    conversa = cena[:mensagens].map { |quem, texto| "#{nomes[quem]}: #{texto}" }.join("\n")
    quem_recebe = recebe(cena).agent.name
    texto = "Conversa:\n#{conversa}\n(Aqui a conversa foi passada para #{quem_recebe}.)\n\nCritério do que é certo: " \
            "#{cena[:certo]}\n\nMensagem de #{quem_recebe}: #{resposta}"
    cliente = Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve,
                                           feature: 'eval_juiz', account: conta)
    raw = cliente.create(model: AvaliacaoAoReceberPassagem::JUIZ, instructions: AvaliacaoAoReceberPassagem::INSTRUCAO_DO_JUIZ,
                         input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)],
                         schema: AvaliacaoAoReceberPassagem::VEREDITO)
    JSON.parse(raw[:text])
  end

  def veredito_bom?(veredito)
    veredito['atende_o_certo'] &&
      %w[repete_a_pessoa assume_promessa_da_pessoa usa_a_nota_privada se_anuncia_como_ia].none? { |campo| veredito[campo] }
  end

  def rodar(cena, vez)
    conversa, passagem = montar_conversa(cena)
    vinculo = recebe(cena)
    Autonomia::Agents::Operate::ResponderAPassagem.new(conversation: conversa, agent_inbox: vinculo, passagem: passagem).perform
    postada = conversa.messages.outgoing.where(sender_type: 'AgentBot', sender_id: vinculo.agent_bot_id).pick(:content).to_s
    # Calou: certo só onde calar é aceitável; não chama o juiz (não há o que julgar).
    veredito = postada.present? ? julgar(cena, postada) : nil
    aprovada = veredito ? veredito_bom?(veredito) : cena[:pode_calar]
    { cena: cena[:nome], execucao: vez, calou: postada.blank?, resposta: postada, veredito: veredito, aprovada: aprovada,
      custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  def cenas_escolhidas
    nome = ENV.fetch('AO_RECEBER_PASSAGEM_EVAL_CENA', nil).presence
    escolhidas = nome ? AvaliacaoAoReceberPassagem::CENAS.select { |cena| cena[:nome] == nome } : AvaliacaoAoReceberPassagem::CENAS
    expect(escolhidas).not_to be_empty, "cena desconhecida: #{nome}"
    escolhidas
  end

  def rodar_todas
    cenas_escolhidas.product((1..AvaliacaoAoReceberPassagem::REPETICOES).to_a).each do |cena, vez|
      break if custo_ate_agora >= AvaliacaoAoReceberPassagem::TETO_USD

      relatorio << rodar(cena, vez)
    end
  end

  def placar
    por_cena = relatorio.group_by { |linha| linha[:cena] }.transform_values do |linhas|
      { aprovadas: linhas.count { |linha| linha[:aprovada] }, calou: linhas.count { |linha| linha[:calou] }, de: linhas.size }
    end
    { execucoes: relatorio.size, aprovadas: relatorio.count { |linha| linha[:aprovada] }, por_cena: por_cena,
      custo_usd: custo_ate_agora.round(4) }
  end

  it 'quem recebe a passagem lê tudo e decide se fala ou cala' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['AO_RECEBER_PASSAGEM_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, AO_RECEBER_PASSAGEM_EVAL=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    vinculos

    rodar_todas

    total = cenas_escolhidas.size * AvaliacaoAoReceberPassagem::REPETICOES
    resultado = placar
    destino = ENV.fetch('AO_RECEBER_PASSAGEM_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(placar: resultado, execucoes: relatorio)) if destino.present?
    expect(relatorio.size).to eq(total), "teto de custo atingido: #{relatorio.size} de #{total} execuções"
    expect(resultado[:aprovadas]).to be >= total - AvaliacaoAoReceberPassagem::MAXIMO_DE_REPROVADAS
  end
end
