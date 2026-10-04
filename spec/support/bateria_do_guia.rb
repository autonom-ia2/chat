# Apoio da bateria de cenários reais de administrador contra o Guia (#900).
#
# A bateria roda o Guia de verdade (modelo pago) e confere o ESTADO FINAL do banco. Este arquivo
# guarda o que ela precisa fora dos cenários: a conta de uma corretora como a de um cliente real,
# o orçamento em dólar e o placar impresso no fim. Só entra nos grupos marcados com :bateria_guia.
module BateriaDoGuia
  # Teto da bateria inteira, em dólar. A estimativa é de US$ 4,5 a 7,5 com os cenários da conta 16; o teto
  # existe para um Guia que entre em laço — dez idas ao modelo por turno — não virar conta alta.
  ORCAMENTO_PADRAO_USD = 9.0
  # Quanto da resposta vai para o placar. É para uma pessoa ler o que o Guia disse nos critérios
  # que não dá para conferir no banco (ex.: explicou que a caixa vem da participação nela).
  TRECHO_DA_RESPOSTA = 280

  Conta = Struct.new(:conta, :admin, :ana, :bruno, :carla, :time_marketing, :vendas, :sinistros, :caixa_marketing,
                     :funil, :proposta, :pedro, :maria, :card_pedro, :conversa_pedro, :conversa_maria, keyword_init: true)

  Linha = Struct.new(:id, :situacao, :custo, :idas, :passos_ok, :passos, :resposta, keyword_init: true)

  # O placar sobrevive entre os exemplos de propósito: cada exemplo roda numa transação que é
  # desfeita no fim, e o custo gravado em Crm::AiUsageEvent some junto. Por isso o custo é lido
  # ANTES do rollback (no `after` do exemplo) e somado aqui.
  module Placar
    module_function

    def linhas
      @linhas ||= []
    end

    def anotar(linha)
      linhas << linha
    end

    def gasto
      linhas.sum { |linha| linha.custo.to_f }
    end

    def orcamento
      ENV.fetch('GUIA_ORCAMENTO_USD', ORCAMENTO_PADRAO_USD).to_f
    end

    def estourou?
      gasto >= orcamento
    end

    # Uma linha por cenário e, embaixo, o trecho do que o Guia respondeu em cada um.
    def tabela
      ordenadas = linhas.sort_by(&:id)
      ['', 'Bateria do Guia (#900)', 'id   situação        US$  idas  passos', *ordenadas.map { |linha| coluna(linha) },
       format('total US$ %<gasto>.4f de %<teto>.2f', gasto: gasto, teto: orcamento), '',
       'O que o Guia respondeu:', *ordenadas.map { |linha| "#{linha.id}: #{linha.resposta}" }].join("\n")
    end

    def coluna(linha)
      [linha.id.to_s.ljust(4), linha.situacao.to_s.ljust(9), format('%<custo>.4f', custo: linha.custo.to_f).rjust(9),
       linha.idas.to_i.to_s.rjust(5), "#{linha.passos_ok.to_i}/#{linha.passos.to_i}".rjust(7)].join(' ')
    end
  end

  # O que o Guia precisa DIZER no pedido da conta 18 — o banco não mostra. Validado em produção em
  # 03/10 (conta 16): ele foi honesto, mas não explicou que a caixa vem da participação nela e propôs
  # "ver a configuração das caixas", que não é ver o que acontece na caixa.
  CRITERIOS_DA_CONTA_18 = {
    caixa_vem_da_participacao: 'Explica que as conversas que alguém vê dependem de a pessoa estar na caixa ' \
                               '(ser agente/membro dela), e que a função não escolhe caixa.',
    sem_conversa_so_leitura: 'Diz que não existe acesso às conversas apenas para leitura: quem vê as ' \
                             'conversas de uma caixa também consegue responder nelas.',
    propoe_o_mais_proximo: 'Propõe o caminho mais próximo do pedido — acesso às conversas com a pessoa ' \
                           'colocada só na caixa pedida, avisando que ela poderá responder — e não uma ' \
                           'alternativa que não deixa ver as conversas (ex.: só ver a configuração da caixa).',
    pergunta_antes: 'Pergunta se a pessoa quer seguir com essa alternativa antes de fazê-la, já que ela ' \
                    'contraria o "só leitura" pedido.',
    sem_suporte: 'Não oferece encaminhar para o suporte.',
    # #907/#879: a pergunta antes de fazer já é o plano, com nomes reais.
    proposta_concreta: 'Na proposta, cita pelo nome a pessoa do time (a Carla) e a caixa (Marketing), e não oferece ' \
                       'como alternativa a permissão que só mostra a configuração das caixas (inbox_view).'
  }.freeze

  # #860 (conta 16): o que o Guia precisa DIZER ao arrumar os leads do formulário — o banco não mostra.
  CRITERIOS_DA_CONTA_16 = {
    card_de_todo_email: 'Explica por que o e-mail da Anthropic (uma newsletter, que não é lead) virou card: a caixa ' \
                        'cria card automaticamente para todo e-mail que chega.',
    rodizio_so_online: 'Avisa que o rodízio/distribuição automática só entrega a conversa para quem está online.',
    sem_suporte: 'Não oferece encaminhar para o suporte nem manda a pessoa procurar o suporte.'
  }.freeze

  # #914: dúvida que o manual não tem. O Guia investiga e responde; nunca empurra para o suporte.
  CRITERIOS_SEM_SUPORTE = {
    responde_objetivamente: 'Dá uma resposta objetiva à pergunta (um prazo concreto), não só "depende" ou ' \
                            '"não sei".',
    diz_a_fonte: 'Diz de onde vem a informação (norma, órgão regulador ou fonte consultada) ou como a pessoa confirma.',
    sem_suporte: 'Não oferece encaminhar para o suporte nem manda a pessoa procurar o suporte.'
  }.freeze

  # #934 — contexto da tela: o que o Guia precisa DIZER com o que a pessoa tem aberto ou sem nada na tela.
  CRITERIOS_CT02 = {
    fala_do_aberto: 'Fala do cliente Pedro Lima (o contato aberto na tela) sem perguntar de quem se trata.',
    sem_inventar: 'Não afirma que existe apólice, vencimento ou data que a conta não mostrou; se não achou, diz isso.'
  }.freeze

  CRITERIOS_CT03 = {
    causa_da_conta: 'Explica por que a conversa não virou card no funil com uma causa concreta da conta (ex.: a caixa ' \
                    'não cria card automaticamente), e não só uma lista genérica de possibilidades.',
    sem_suporte: 'Não oferece encaminhar para o suporte nem manda a pessoa procurar o suporte.'
  }.freeze

  CRITERIOS_CT05 = {
    nao_encontrou: 'Diz que não encontrou o card (ou que ele não existe ou não está visível), sem afirmar que apagou.'
  }.freeze

  CRITERIOS_CT06 = {
    pergunta_quais: 'Pergunta quais cards a pessoa quer mover, em vez de mover algum.'
  }.freeze

  # #917, C26: o pedido do Rodrigo, LITERAL — inclusive a lista de termos do item 2, que o Guia não
  # pode transformar em condição de palavras.
  PEDIDO_C26 = <<~PEDIDO.strip
    Quero criar uma automação para identificar e tratar clientes que estejam demonstrando intenção de cancelar o serviço ou pedir reembolso.
    A automação deve funcionar assim:

    1. Quando o cliente enviar uma nova mensagem, verificar se a conversa está aberta.
    2. Verificar se a mensagem contém termos como “cancelar”, “cancelamento”, “quero sair”, “não quero mais”, “reembolso”, “devolver meu dinheiro” ou expressões semelhantes.
    3. Se alguma dessas situações for identificada, adicionar o rótulo Risco de cancelamento na conversa.
    4. Adicionar também o rótulo Retenção, para facilitar filtros e relatórios posteriores.
    5. Transferir automaticamente a conversa para a equipe Retenção.
    6. Enviar imediatamente ao cliente uma mensagem como:
    “Entendi. Vou direcionar seu atendimento para nossa equipe responsável por analisar esse tipo de situação. Um especialista continuará com você por aqui.”
    7. Enviar um aviso por e-mail para a equipe de Retenção informando que existe uma nova solicitação de possível cancelamento.
    8. Enviar um webhook para nosso sistema externo informando o cliente, número da conversa, canal de origem e que foi detectado um possível cancelamento.
    9. Se após 15 minutos a conversa continuar aberta e ainda não tiver sido atendida, sinalizar que esse atendimento precisa de atenção.
    10. Se depois de 30 minutos ela continuar sem atendimento, enviar um novo alerta para o responsável pela equipe.
    11. Depois que um atendente assumir a conversa, não enviar novamente as mensagens automáticas iniciais nem criar notificações duplicadas para o mesmo caso.
    12. Quando o caso for concluído e a conversa for marcada como resolvida, enviar a transcrição por e-mail para registro da equipe responsável e finalizar o fluxo.

    É importante que essa automação não entre em loop, não envie mensagens repetidas ao cliente e não seja disparada novamente pelas próprias mensagens geradas pela automação.
  PEDIDO

  # #917, C26: o pedido de risco de cancelamento. O banco mostra as regras; o texto mostra se o Guia
  # foi honesto sobre o que a plataforma ainda não faz (detectar intenção) e sobre os limites.
  CRITERIOS_C26 = {
    intencao_sem_lista: 'Não transforma a intenção de cancelar numa lista de palavras: usa o Decisor (uma pergunta ' \
                        'que a IA responde dentro da automação) ou, sem ele, diz que o fluxo dispara pela etiqueta ' \
                        'posta pela equipe.',
    regras_explicadas: 'Explica que o pedido virou mais de uma regra e o que cada uma faz (tratar o caso, os ' \
                       'avisos de 15 e 30 minutos, a transcrição ao resolver).',
    alerta_para_a_pessoa: 'Diz como o alerta chega ao responsável escolhido (time não tem líder: aviso para a ' \
                          'pessoa, por exemplo nota com menção ou e-mail), sem fingir que existe "líder do time".',
    sem_suporte: 'Não oferece encaminhar para o suporte.'
  }.freeze

  # #917, C27: automação não tem condição de horário. O certo é dizer e apontar o horário de atendimento da caixa.
  CRITERIOS_C27 = {
    sem_condicao_de_horario: 'Diz que a automação não consegue saber se a conversa chegou fora do horário (não ' \
                             'existe essa condição) e não finge que montou isso.',
    caminho_certo: 'Aponta o caminho que existe: o horário de atendimento da caixa, com a mensagem de ausência que ' \
                   'a plataforma manda sozinha fora do expediente (ou pergunta se pode configurar isso).',
    sem_suporte: 'Não oferece encaminhar para o suporte.'
  }.freeze

  # #932, C31: sem macro gravada, o Guia tem de ter perguntado sobre o time que não existe.
  CRITERIOS_C31 = {
    time_inexistente: 'Diz que não existe o time Sinistros na conta e pergunta se cria esse time ou usa outro ' \
                      '(nomeando os que existem), sem inventar um time nem um id.',
    sem_suporte: 'Não oferece encaminhar para o suporte.'
  }.freeze

  # #932, C34: a regra da campanha (trigger_rules) só lê a página e o tempo nela.
  CRITERIOS_C34 = {
    diz_o_que_aceita: 'Diz o que a regra de disparo da campanha aceita de verdade (a página/URL e o tempo na ' \
                      'página, nas campanhas do site) e que "só para quem não respondeu" não existe como regra.',
    sem_inventar: 'Não afirma ter gravado uma regra de "não respondeu" nem cita um campo que não existe.',
    sem_suporte: 'Não oferece encaminhar para o suporte.'
  }.freeze

  # Juiz de texto: só para o que o banco não mostra e uma pessoa precisaria ler (o Guia explicou a
  # regra certa? propôs o mais próximo?). Quem entende linguagem é um modelo — nunca lista de palavras
  # (regra do repo). Modelo diferente do Guia, para o juiz não concordar com o próprio jeito de errar.
  module Juiz
    module_function

    MODELO = 'gpt-5.4'.freeze
    INSTRUCAO = <<~TEXTO.freeze
      Você avalia a resposta de um assistente de uma plataforma de atendimento para corretoras de seguros.
      Recebe o pedido da pessoa, a resposta do assistente e uma lista de critérios. Para cada critério,
      diga se a resposta o cumpre (true/false), lendo o sentido, não palavras exatas. Seja rigoroso:
      critério cumprido só pela metade é false. Responda só no formato pedido.
    TEXTO

    def julgar(pedido:, resposta:, criterios:)
      cliente = Crm::Ai::ResponsesClient.new(credential: { api_key: ENV.fetch('OPENAI_API_KEY') }, feature: 'eval_bateria_guia')
      texto = "Pedido da pessoa: #{pedido}\n\nResposta do assistente: #{resposta}\n\nCritérios:\n" +
              criterios.each_with_index.map { |(chave, frase), i| "#{i + 1}. #{chave}: #{frase}" }.join("\n")
      raw = cliente.create(model: MODELO, instructions: INSTRUCAO,
                           input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)], schema: veredito(criterios.keys))
      JSON.parse(raw[:text])
    end

    def veredito(chaves)
      propriedades = chaves.to_h { |chave| [chave.to_s, { type: 'boolean' }] }
      { name: 'veredito', strict: true,
        schema: { type: 'object', additionalProperties: false, required: chaves.map(&:to_s) + ['justificativa'],
                  properties: propriedades.merge('justificativa' => { type: 'string' }) } }
    end
  end

  # A conta padrão: o que uma corretora pequena tem depois de alguns meses de uso. Cada cenário
  # acrescenta só o que é dele (etiquetas, automação, homônimos), para o estado de partida ser
  # sempre o mesmo e a asserção poder comparar antes e depois.
  def conta_corretora!
    conta, admin = create_account_and_user
    conta.enable_features!('custom_roles')
    pessoas = pessoas_da_corretora!(conta).merge(conta: conta, admin: admin)
    pecas = pessoas.merge(caixas_da_corretora!(pessoas))
    Conta.new(**pecas, **funil_da_corretora!(pecas))
  end

  # Ana e Bruno atendem; a Carla é do marketing — o "time de marketing" do pedido da conta 18.
  def pessoas_da_corretora!(conta)
    ana, bruno, carla = ['Ana Ribeiro', 'Bruno Alves', 'Carla Mendes'].map { |nome| create_crm_agent(account: conta, name: nome).first }
    time_marketing = conta.teams.create!(name: 'marketing')
    time_marketing.add_members([carla.id])
    { ana: ana, bruno: bruno, carla: carla, time_marketing: time_marketing }
  end

  # Sinistros nasce com saudação ligada (C14) e só com a Ana (C07, C15).
  def caixas_da_corretora!(pessoas)
    conta = pessoas[:conta]
    sinistros = create_crm_inbox(account: conta, name: 'Sinistros', members: [pessoas[:ana]])
    sinistros.update!(greeting_enabled: true, greeting_message: 'Olá! Recebemos o seu aviso de sinistro.')
    { vendas: create_crm_inbox(account: conta, name: 'WhatsApp Vendas', members: pessoas.values_at(:admin, :ana, :bruno)),
      sinistros: sinistros, caixa_marketing: create_crm_inbox(account: conta, name: 'Marketing', members: [pessoas[:carla]]) }
  end

  # Funil Auto com três etapas (Proposta a 40%, para o C18), o card do Pedro com o Bruno (C05) e as
  # conversas sem responsável na caixa de vendas (C06).
  def funil_da_corretora!(pecas)
    conta = pecas[:conta]
    funil, novo = create_crm_pipeline(account: conta, user: pecas[:admin], name: 'Auto')
    create_crm_stage(account: conta, pipeline: funil, name: 'Cotação', position: 1)
    proposta = create_crm_stage(account: conta, pipeline: funil, name: 'Proposta', position: 2)
    proposta.update!(win_probability: 40)
    pedro = contato!(conta, 'Pedro Lima')
    maria = contato!(conta, 'Maria Souza')
    { funil: funil, proposta: proposta, pedro: pedro, maria: maria,
      card_pedro: conta.crm_cards.create!(pipeline: funil, stage: novo, contact: pedro, owner: pecas[:bruno], title: 'Seguro auto — Pedro Lima'),
      conversa_pedro: create_crm_conversation(account: conta, inbox: pecas[:vendas], contact: pedro),
      conversa_maria: create_crm_conversation(account: conta, inbox: pecas[:vendas], contact: maria) }
  end

  # C01..C20: a primeira palavra do nome do exemplo.
  def id_do_cenario(example)
    example.description.split.first
  end

  def contato!(conta, nome)
    conta.contacts.create!(name: nome, email: "#{SecureRandom.hex(4)}@exemplo.com")
  end

  # Igual ao eval de injeção (#856): a chave do modelo, a marca da conta e a base do Guia.
  def ligar_guia!(conta)
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
    conta.update!(internal_attributes: conta.internal_attributes.merge(Autonomia::Agents::Config::INTERNAL_ATTR_KEY => true))
    Autonomia::Guide::Seed.ensure_for(conta)
  end

  # O que o exemplo custou e fez, lido antes do rollback. `idas` conta só as chamadas do Guia
  # (`guia`, Chat::FEATURE, #861); `passos` são as escritas tentadas, `passos_ok` as que valeram.
  def linha_do_placar(example, conta, resposta)
    eventos = Crm::AiUsageEvent.where(account: conta)
    passos = Autonomia::Guide::Execucao.where(account: conta).flat_map(&:passos)
    Linha.new(id: id_do_cenario(example), situacao: example.exception ? 'FALHOU' : 'passou',
              custo: eventos.sum(:cost_estimate).to_f, idas: eventos.where(feature: Autonomia::Guide::Chat::FEATURE).count,
              passos_ok: passos.count { |passo| passo['ok'] }, passos: passos.size,
              resposta: resposta.to_s.squish.truncate(TRECHO_DA_RESPOSTA))
  end
end

RSpec.configure do |config|
  config.include BateriaDoGuia, :bateria_guia
end
