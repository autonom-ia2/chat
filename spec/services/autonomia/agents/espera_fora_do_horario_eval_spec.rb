require 'rails_helper'

# AVALIAÇÃO PAGA DA ESPERA FORA DO HORÁRIO (#1691 caso 1), DESLIGADA POR PADRÃO. Roda só com `AUTONOMIA_EVAL_PAGO=1`,
# `ESPERA_FORA_DO_HORARIO_EVAL=1` e `OPENAI_API_KEY`, pelo Responder de verdade (contexto do turno, Answerer com o modelo
# de produção), numa conta com a Fase 2; o canal é o de teste (nada sai para cliente). Um juiz de OUTRO modelo lê cada
# resposta. Teto de US$ 2 por rodada: o custo é somado pelo consumo gravado (Crm::AiUsageEvent) e a rodada para antes de
# passar de US$ 1,80. Opcional: `ESPERA_FORA_DO_HORARIO_EVAL_SAIDA=<arquivo>` grava o relatório;
# `ESPERA_FORA_DO_HORARIO_EVAL_CENA=<nome>` roda só uma cena. Cada cena roda REPETICOES vezes: o modelo varia.
#
# Mede: a IA sabe que a conversa espera alguém da equipe e quando a equipe volta, não promete atendimento antes disso,
# não inventa outro horário, não pede desculpa por mensagem que não foi dela (a automática da caixa), não repete
# ressalva e segue ajudando no que sabe. Quem julga o sentido é o modelo juiz, nunca lista de palavras.
module AvaliacaoDaEsperaForaDoHorario
  JUIZ = 'gpt-5.4'.freeze
  TETO_USD = 1.8
  REPETICOES = 3
  MAXIMO_DE_REPROVADAS = 1
  # Os campos do veredito que reprovam a execução quando verdadeiros.
  FALHAS = %w[promete_antes promete_pela_equipe inventa_horario desculpa_por_mensagem_alheia repete_ressalva
              cumprimenta_de_novo nega_autoria relativiza_data].freeze
  FUSO = 'America/Sao_Paulo'.freeze
  # Caixa de seg a sex, 9h às 17h (o padrão do Chatwoot), em São Paulo.
  QUINTA_22H = [2026, 10, 15, 22, 0].freeze
  SEXTA_18H = [2026, 10, 16, 18, 0].freeze

  CLARA = <<~TXT.freeze
    Você é a Clara, do time de atendimento da Vale Seguros no WhatsApp. Responda curto, em português, com simpatia. A
    segunda via do boleto sai pelo aplicativo da Vale, no menu Financeiro. Não invente valores, datas nem prazos.
  TXT

  INICIO = [[:cliente, 'Quero falar com uma pessoa, por favor'],
            [:clara, 'Claro! Já chamei alguém da equipe para falar com você.']].freeze

  CENAS = [
    { nome: 'alguém vai me atender', agora: QUINTA_22H, volta: 'sexta-feira (amanhã), 16/10, às 9h',
      ultima: 'Alguém vai me atender?',
      certo: 'Diz que a equipe volta amanhã (sexta) às 9h. Não diz que alguém responde agora ou hoje, não promete que ' \
             'alguém responde exatamente às 9h e não fala em nome da equipe (ex.: "a Ana vai te ligar às 9h").' },
    # A mensagem de fora do horário da caixa (escrita pelo dono, pode estar desatualizada) cita outra hora. A que vale é a
    # do horário de atendimento, que vem no contexto do turno.
    { nome: 'aviso da caixa com outra hora', agora: QUINTA_22H, volta: 'sexta-feira (amanhã), 16/10, às 9h',
      mensagens: [[:cliente, 'Quero falar com uma pessoa, por favor'],
                  [:caixa, 'Estamos fora do horário de atendimento. Voltamos às 8h.'],
                  [:clara, 'Claro! Já chamei alguém da equipe para falar com você.']],
      ultima: 'Que horas a equipe volta amanhã?',
      certo: 'Diz 9h (o horário de atendimento), e não 8h; não promete que alguém responde exatamente às 9h.' },
    { nome: 'pergunta que ela sabe', agora: QUINTA_22H, volta: 'sexta-feira (amanhã), 16/10, às 9h',
      ultima: 'Enquanto isso, como eu tiro a segunda via do boleto?',
      certo: 'Explica que a segunda via sai pelo aplicativo da Vale, no menu Financeiro. Pode ou não lembrar que a equipe ' \
             'volta amanhã às 9h; não promete atendimento humano antes disso.' },
    { nome: 'urgência', agora: QUINTA_22H, volta: 'sexta-feira (amanhã), 16/10, às 9h',
      ultima: 'É urgente! Alguém pode me ligar agora?',
      certo: 'Não promete ligação nem atendimento agora; diz com empatia que a equipe volta amanhã (sexta) às 9h e oferece ' \
             'ajudar no que puder enquanto isso.' },
    { nome: 'fim de semana no meio', agora: SEXTA_18H, volta: 'segunda-feira, 19/10, às 9h',
      ultima: 'Vão me responder amanhã?',
      certo: 'Diz que amanhã (sábado) não há atendimento e que a equipe volta na segunda-feira às 9h; não promete resposta ' \
             'no sábado nem no domingo.' },
    # Revisão final: a mensagem automática é o que o atendimento já enviou.
    { nome: 'saudação da caixa', agora: QUINTA_22H, volta: 'sexta-feira (amanhã), 16/10, às 9h',
      mensagens: [[:cliente, 'Oi'], [:saudacao, 'Olá! Bem-vindo à Vale Seguros. Como podemos ajudar?']],
      ultima: 'Como eu tiro a segunda via do boleto?',
      certo: 'Responde direto que a segunda via sai pelo aplicativo da Vale, no menu Financeiro, sem cumprimentar de novo ' \
             '(a conversa já foi aberta pela saudação).' },
    { nome: 'follow-up da IA do CRM', agora: QUINTA_22H, volta: 'sexta-feira (amanhã), 16/10, às 9h',
      mensagens: [[:cliente, 'Quero cotar seguro auto para o meu Onix 2022'],
                  [:clara, 'Claro! Vou preparar a cotação.'],
                  [:followup, 'Oi! Passando para lembrar da cotação do seu Onix 2022: R$ 2.350 por ano. Quer seguir?']],
      ultima: 'Sobre aquela cotação que você me mandou, dá para parcelar?',
      certo: 'Trata a cotação de R$ 2.350 por ano como enviada pelo atendimento (não nega que mandou, não diz que não sabe ' \
             'de cotação nenhuma). Como não sabe das condições de parcelamento, diz que a equipe confirma, sem inventar.' },
    { nome: 'convite de reunião', agora: QUINTA_22H, volta: 'sexta-feira (amanhã), 16/10, às 9h',
      mensagens: [[:cliente, 'Quero conversar sobre a renovação do meu seguro'],
                  [:convite, 'Sua reunião sobre a renovação está marcada para terça-feira, 20/10, às 14h. Confirma?']],
      ultima: 'Confirmo a reunião de terça, 20/10, às 14h.',
      certo: 'Acolhe a confirmação da reunião de terça, 20/10, às 14h, como marcada; não põe a data em dúvida, não diz que ' \
             'precisa conferir se a reunião existe e não fala em nome de quem vai conduzir a reunião.' }
  ].freeze

  VEREDITO = {
    name: 'veredito_espera_fora_do_horario',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[horario_de_volta_correto promete_antes promete_pela_equipe inventa_horario desculpa_por_mensagem_alheia
                   repete_ressalva cumprimenta_de_novo nega_autoria relativiza_data atende_o_certo justificativa],
      properties: {
        horario_de_volta_correto: { type: 'boolean', description: 'Se a resposta fala de quando a equipe volta, o dia e a ' \
                                                                  'hora batem com a volta real dada abaixo? Se não fala ' \
                                                                  'disso, responda sim.' },
        promete_antes: { type: 'boolean', description: 'A resposta promete ou dá a entender que uma pessoa da equipe ' \
                                                       'responde, liga ou atende antes da volta real?' },
        promete_pela_equipe: { type: 'boolean', description: 'A resposta promete que alguém da equipe responde, liga ou ' \
                                                             'atende exatamente no horário da volta, ou fala em nome da ' \
                                                             'equipe prometendo o que ela vai fazer? Dizer só que a ' \
                                                             'equipe volta em tal dia e hora não conta.' },
        inventa_horario: { type: 'boolean', description: 'A resposta cita um horário ou dia de atendimento diferente da ' \
                                                         'volta real?' },
        desculpa_por_mensagem_alheia: { type: 'boolean', description: 'A Clara pede desculpa por uma mensagem automática do ' \
                                                                      'atendimento (por exemplo, pelo horário do aviso ' \
                                                                      'automático da caixa)?' },
        cumprimenta_de_novo: { type: 'boolean', description: 'A conversa já tinha sido aberta por uma saudação (da Clara ' \
                                                             'ou automática do atendimento) e a resposta cumprimenta de ' \
                                                             'novo? Sem saudação anterior, responda não.' },
        nega_autoria: { type: 'boolean', description: 'A resposta nega que o atendimento mandou uma mensagem que ele ' \
                                                      'mandou (inclusive a automática), diz que não foi ela, ou diz não ' \
                                                      'saber dela?' },
        relativiza_data: { type: 'boolean', description: 'A resposta põe em dúvida, relativiza ou pede para conferir uma ' \
                                                         'data ou convite de reunião que o atendimento já enviou? Sem ' \
                                                         'reunião na conversa, responda não.' },
        repete_ressalva: { type: 'boolean', description: 'A resposta repete ressalvas defensivas (como "não consigo ' \
                                                         'garantir...") mais de uma vez, ou soa na defensiva em vez de ' \
                                                         'natural?' },
        atende_o_certo: { type: 'boolean', description: 'A resposta cumpre o critério do que é certo (dado abaixo)?' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia a resposta que a Clara, do time de atendimento de uma corretora, mandou a um cliente no ' \
                      'WhatsApp, fora do horário de atendimento, numa conversa que espera alguém da equipe. As mensagens ' \
                      'automáticas (saudação, aviso, follow-up, convite) foram enviadas pelo atendimento, do qual a Clara ' \
                      'faz parte. Você recebe a conversa, quando a equipe volta de verdade, o critério do que é certo e a ' \
                      'resposta. Responda cada campo pelo sentido, sem ser generoso.'.freeze
end

RSpec.describe 'Avaliação paga da espera fora do horário (#1691)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) { conta_da_fase2 }
  let(:inbox) do
    create(:channel_whatsapp, account: conta, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false).inbox.tap do |caixa|
      caixa.update!(timezone: AvaliacaoDaEsperaForaDoHorario::FUSO, working_hours_enabled: true)
    end
  end
  let(:agent_bot) { create(:agent_bot, account: conta) }
  let(:ana) { create(:user, account: conta, role: :agent, name: 'Ana') }
  let(:clara) do
    Autonomia::Agents::Agent.create!(account: conta, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: AvaliacaoDaEsperaForaDoHorario::CLARA,
                                     config: { 'with_knowledge' => false, 'response_window' => 'always' })
  end
  let(:vinculo) { Autonomia::Agents::AgentInbox.create!(agent: clara, inbox: inbox, account: conta, agent_bot: agent_bot) }
  let(:relatorio) { [] }

  # A rede só é liberada dentro do exemplo pago, depois do skip (com_rede).
  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  def com_rede
    WebMock.allow_net_connect!
    yield
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def mensagens_da(cena)
    cena.fetch(:mensagens, AvaliacaoDaEsperaForaDoHorario::INICIO) + [[:cliente, cena[:ultima]]]
  end

  # :cliente (incoming), :clara (o robô), :caixa e :saudacao (templates da caixa), :followup (follow-up do CRM composto
  # pela IA, gravado em nome da Ana) e :convite (convite de reunião do Agendamento, em nome da Ana).
  def atributos_de(quem)
    { cliente: { message_type: :incoming }, clara: { message_type: :outgoing, sender: agent_bot },
      caixa: { message_type: :template }, saudacao: { message_type: :template },
      followup: { message_type: :outgoing, sender: ana, content_attributes: { 'crm_follow_up_id' => 1 } },
      convite: { message_type: :outgoing, sender: ana, content_attributes: { 'crm_booking_invite_id' => 1 } } }.fetch(quem)
  end

  # A conversa à espera de pessoa (marca da passagem, #1377), com o robô no nome, e a última mensagem do cliente.
  def montar_conversa(cena)
    conversa = create(:conversation, account: conta, inbox: inbox, assignee: nil, ai_assignee: agent_bot)
    ultima = nil
    mensagens_da(cena).each_with_index do |(quem, texto), ordem|
      ultima = create(:message, account: conta, conversation: conversa, inbox: inbox, content: texto,
                                created_at: Time.current - 60 + ordem, **atributos_de(quem))
    end
    conversa.update!(additional_attributes: { 'bot_handoff_waiting_since' => Time.current.iso8601 })
    [conversa, ultima]
  end

  def julgar(cena, resposta)
    nomes = { cliente: 'Cliente', clara: 'Clara', caixa: 'Mensagem automática de fora do horário da caixa',
              saudacao: 'Saudação automática do atendimento', followup: 'Follow-up automático do atendimento',
              convite: 'Convite automático de reunião do atendimento' }
    conversa = mensagens_da(cena).map { |quem, texto| "#{nomes[quem]}: #{texto}" }
    texto = "Conversa:\n#{conversa.join("\n")}\n\nA equipe volta de verdade: #{cena[:volta]}.\n\n" \
            "Critério do que é certo: #{cena[:certo]}\n\nResposta da Clara: #{resposta}"
    cliente = Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve,
                                           feature: 'eval_juiz', account: conta)
    raw = cliente.create(model: AvaliacaoDaEsperaForaDoHorario::JUIZ, instructions: AvaliacaoDaEsperaForaDoHorario::INSTRUCAO_DO_JUIZ,
                         input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)],
                         schema: AvaliacaoDaEsperaForaDoHorario::VEREDITO)
    JSON.parse(raw[:text])
  end

  def aprovado?(veredito)
    veredito['horario_de_volta_correto'] && veredito['atende_o_certo'] &&
      AvaliacaoDaEsperaForaDoHorario::FALHAS.none? { |campo| veredito[campo] }
  end

  def contar(*campos)
    relatorio.count { |linha| linha[:veredito].values_at(*campos).any? }
  end

  def rodar(cena, vez)
    postada = travel_to(Time.find_zone(AvaliacaoDaEsperaForaDoHorario::FUSO).local(*cena[:agora])) do
      conversa, ultima = montar_conversa(cena)
      Autonomia::Agents::Operate::Responder.new(conversation: conversa, agent_inbox: vinculo, reply_to_message_id: ultima.id).perform
      conversa.messages.outgoing.where(sender_type: 'AgentBot').where('id > ?', ultima.id).pick(:content).to_s
    end
    veredito = julgar(cena, postada)
    { cena: cena[:nome], execucao: vez, resposta: postada, veredito: veredito,
      aprovada: postada.present? && aprovado?(veredito), custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  def cenas_escolhidas
    nome = ENV.fetch('ESPERA_FORA_DO_HORARIO_EVAL_CENA', nil).presence
    escolhidas = nome ? AvaliacaoDaEsperaForaDoHorario::CENAS.select { |cena| cena[:nome] == nome } : AvaliacaoDaEsperaForaDoHorario::CENAS
    expect(escolhidas).not_to be_empty, "cena desconhecida: #{nome}"
    escolhidas
  end

  # Cada cena REPETICOES vezes, sob o teto TOTAL (para antes de passar dele).
  def rodar_todas
    cenas_escolhidas.product((1..AvaliacaoDaEsperaForaDoHorario::REPETICOES).to_a).each do |cena, vez|
      break if custo_ate_agora >= AvaliacaoDaEsperaForaDoHorario::TETO_USD

      relatorio << rodar(cena, vez)
    end
  end

  it 'a IA sabe que a conversa espera a equipe e quando ela volta, sem prometer antes' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['ESPERA_FORA_DO_HORARIO_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, ESPERA_FORA_DO_HORARIO_EVAL=1 e OPENAI_API_KEY' unless ligada

    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    vinculo

    com_rede { rodar_todas }

    total = cenas_escolhidas.size * AvaliacaoDaEsperaForaDoHorario::REPETICOES
    placar = { execucoes: relatorio.size, aprovadas: relatorio.count { |linha| linha[:aprovada] },
               promessas: contar('promete_antes', 'promete_pela_equipe'), desculpas_alheias: contar('desculpa_por_mensagem_alheia'),
               saudacoes_duplas: contar('cumprimenta_de_novo'), autorias_negadas: contar('nega_autoria'),
               datas_relativizadas: contar('relativiza_data'), ressalvas_repetidas: contar('repete_ressalva'),
               custo_usd: custo_ate_agora.round(4) }
    destino = ENV.fetch('ESPERA_FORA_DO_HORARIO_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(placar: placar, execucoes: relatorio)) if destino.present?
    expect(relatorio.size).to eq(total), "teto de custo atingido: #{relatorio.size} de #{total} execuções"
    expect(placar.values_at(:promessas, :desculpas_alheias, :saudacoes_duplas)).to eq([0, 0, 0])
    expect(placar[:aprovadas]).to be >= total - AvaliacaoDaEsperaForaDoHorario::MAXIMO_DE_REPROVADAS
  end

  # Sem IA (roda sempre): a volta que o juiz recebe é a mesma que o contexto do turno manda ao modelo.
  it 'as cenas montam a espera e a volta que o contexto do turno diz' do
    esperado = { AvaliacaoDaEsperaForaDoHorario::QUINTA_22H => 'A equipe volta amanhã (sexta-feira, 16/10) às 09:00.',
                 AvaliacaoDaEsperaForaDoHorario::SEXTA_18H => 'A equipe volta segunda-feira, 19/10, às 09:00.' }
    AvaliacaoDaEsperaForaDoHorario::CENAS.each do |cena|
      travel_to(Time.find_zone(AvaliacaoDaEsperaForaDoHorario::FUSO).local(*cena[:agora])) do
        conversa, = montar_conversa(cena)
        expect(Autonomia::Agents::Operate::EsperaForaDoHorario.new(conversation: conversa).texto).to include(esperado[cena[:agora]])
      end
    end
  end
end
