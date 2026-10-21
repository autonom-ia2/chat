require 'rails_helper'

# AVALIAÇÃO PAGA DO VOCABULÁRIO DO GUIA (#1802, 6.B), DESLIGADA POR PADRÃO. Roda só com `AUTONOMIA_EVAL_PAGO=1`,
# `GUIA_VOCABULARIO_EVAL=1` e `OPENAI_API_KEY`. Pelo Guia de verdade (Autonomia::Guide::Chat), com o interruptor dos
# pacotes ligado: a base de telas já é a do pacote da conta nas duas variantes. O que muda é só a instrução:
#   - `sem_camada`: a instrução geral, como hoje;
#   - `com_camada`: a geral e, depois dela, lib/operator_guide/pacotes/<camada>/guia-instrucao.md.
# As variantes vão intercaladas (pergunta × variante), e os tipos também: se o teto cortar, a cobertura fica igual.
# O juiz, de outro modelo, não sabe a variante e lê o sentido (nunca lista de palavras). Teto somado pelo consumo
# gravado em Crm::AiUsageEvent, com o juiz incluído; antes de cada execução sobra uma folga para ela caber no teto.
# `GUIA_VOCABULARIO_EVAL_SAIDA=<arquivo>` grava o relatório em JSON. Para rodar só parte (e caber no que sobrou do
# orçamento): `GUIA_VOCABULARIO_EVAL_TIPOS=seguradora,insurtech`, `GUIA_VOCABULARIO_EVAL_PERGUNTAS=p5,p4` (nesta ordem)
# e `GUIA_VOCABULARIO_EVAL_TETO_USD=<valor>`, que só abaixa o teto, nunca passa de TETO_USD.
module AvaliacaoDoVocabulario
  JUIZ = 'gpt-5.4'.freeze
  TETO_USD = 2.0
  # Uma execução começa só se gasto + folga <= teto. A folga é o dobro da execução mais cara já vista, nunca menos que
  # isto: o Guia pode dar até dez idas ao modelo num turno.
  FOLGA_MINIMA_USD = 0.30
  REPETICOES = 1
  VARIANTES = %i[sem_camada com_camada].freeze
  TIPOS = %w[corretora saude_beneficios seguradora insurtech].freeze
  NAO_CORRETORA = %w[seguradora insurtech].freeze

  # As mesmas perguntas em todos os tipos, do jeito que o operador fala (com "vendas" e "cliente" de propósito). As de
  # `tipos:` puxam o critério que importa para quem não é corretora: a pergunta já vem com "cotação".
  PERGUNTAS = [
    { letra: 'p1', texto: 'Quantas vendas eu fechei esse mês?' },
    { letra: 'p2', texto: 'Como cadastro um cliente novo?' },
    { letra: 'p3', texto: 'Onde vejo as propostas paradas?' },
    { letra: 'p4', texto: 'Como marco que o cliente fechou?' },
    { letra: 'p5', texto: 'Como crio uma cotação nova?', tipos: NAO_CORRETORA },
    { letra: 'p6', texto: 'Como faço uma proposta para um cliente?', tipos: NAO_CORRETORA }
  ].freeze

  # O que cada tipo espera ouvir, escrito para o juiz (não é o texto da camada).
  VOCABULARIO_DO_JUIZ = {
    'corretora' => 'Corretora de seguros (intermedia; não é a seguradora, não aprova nem paga sinistro). Quem vende é ' \
                   '"corretor" (nunca vendedor nem produtor); o que se negocia é "cotação"; "cliente" só para quem já ' \
                   'comprou; "segurado" só com apólice; negócio fechado é "fechou o seguro", nunca "ganho".',
    'saude_beneficios' => 'Corretora de planos de saúde e benefícios (não é a operadora). Fala de "plano" e ' \
                          '"beneficiário"; nunca chama ninguém de "segurado"; negócio fechado é "fechou o plano", ' \
                          'nunca "ganho".',
    'seguradora' => 'Seguradora (não é corretora). Fala de seguro, proposta, apólice, sinistro e renovação; nunca chama ' \
                    'a conta, a equipe ou o trabalho dela de corretora, corretor ou cotação; "segurado" só com ' \
                    'apólice; negócio fechado é "fechou o seguro", nunca "ganho".',
    'insurtech' => 'Empresa de seguros digital (não é corretora). Fala de seguro, proposta, apólice, sinistro e ' \
                   'renovação; nunca chama a conta, a equipe ou o trabalho dela de corretora, corretor ou cotação; ' \
                   '"segurado" só com apólice; negócio fechado é "fechou o seguro", nunca "ganho".'
  }.freeze

  RUINS = %w[chama_de_segurado_sem_apolice diz_vendedor_ou_ganho diz_corretora_ou_cotacao].freeze
  BONS = %w[usa_vocabulario_do_tipo correta_e_util].freeze

  VEREDITO = {
    name: 'veredito_vocabulario', strict: true,
    schema: {
      type: 'object', additionalProperties: false,
      required: BONS + RUINS + %w[justificativa],
      properties: {
        usa_vocabulario_do_tipo: { type: 'boolean', description: 'Fala com as palavras do tipo da conta descritas acima?' },
        correta_e_util: { type: 'boolean', description: 'Responde o que foi perguntado de forma útil para quem opera a ' \
                                                        'plataforma (caminho na tela ou o número pedido), coerente com ' \
                                                        'os dados da conta e sem se contradizer?' },
        chama_de_segurado_sem_apolice: { type: 'boolean', description: 'Chama de "segurado" quem não tem apólice ' \
                                                                       '(contato, pessoa em negociação) ou, em plano ' \
                                                                       'de saúde, chama alguém de segurado?' },
        diz_vendedor_ou_ganho: { type: 'boolean', description: 'Chama quem vende de vendedor (ou de produtor, na ' \
                                                               'corretora), ou o negócio fechado de ganho ou venda ganha?' },
        diz_corretora_ou_cotacao: { type: 'boolean', description: 'Só para seguradora e insurtech: chama a conta, a ' \
                                                                  'equipe ou o trabalho dela de corretora, corretor ou ' \
                                                                  'cotação, como palavra dela? O nome de uma tela ou ' \
                                                                  'menu citado como aparece (o menu Cotação) não conta. ' \
                                                                  'Para os outros tipos, false.' },
        justificativa: { type: 'string', description: 'Uma frase.' }
      }
    }
  }.freeze

  INSTRUCAO_DO_JUIZ = 'Você avalia a resposta do assistente interno de uma plataforma de atendimento e CRM. Quem pergunta ' \
                      'é a pessoa que opera a conta. Você recebe o tipo da conta e as palavras que ele usa, os dados da ' \
                      'conta, a pergunta e a resposta. Nome de botão ou menu citado como aparece na tela e nome de funil ou ' \
                      'etapa que a conta criou (Comercial, Novo Lead, Proposta enviada, e o menu Cotação, que existe) não ' \
                      'contam contra o vocabulário. ' \
                      'A pergunta pode usar palavras que o tipo não usa; julgue só a resposta. Responda cada campo pelo ' \
                      'sentido, sem ser generoso.'.freeze

  DADOS_DA_CONTA = 'Funil Comercial, do tipo Vender (o tipo do funil, que aparece como "funil de Vender"), com as etapas ' \
                   'Novo Lead e Proposta enviada. Três cards: um fechado neste mês ' \
                   '(R$ 1.200,00, de Pedro Lima), um aberto em Proposta enviada sem movimento há 20 dias (Maria Souza) ' \
                   'e um aberto em Novo Lead (João Alves). A pessoa que pergunta administra a conta.'.freeze
end

RSpec.describe 'Avaliação paga do vocabulário do Guia (#1802, 6.B)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:relatorio) { [] }
  let(:pulados) { [] }
  let(:contas) { tipos_escolhidos.index_with { |perfil| conta_do_tipo!(perfil) } }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true', AUTONOMIA_PACOTES_ENABLED: 'true' do
      example.run
    end
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  # Nome neutro ("Grupo Vale") e os mesmos dados nos três tipos: o tipo só chega ao Guia pelo pacote.
  def conta_do_tipo!(perfil)
    conta, admin = create_account_and_user
    nicho = Autonomia::Agents::Nicho
    conta.update!(name: 'Grupo Vale', internal_attributes: conta.internal_attributes.merge(
      nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => perfil, Autonomia::Agents::Config::INTERNAL_ATTR_KEY => true
    ))
    funil!(conta, admin)
    Autonomia::Guide::Seed.ensure_for(conta) || raise("Guia não semeou na conta #{perfil}")
    { conta: conta, admin: admin }
  end

  def funil!(conta, admin)
    funil, novo = create_crm_pipeline(account: conta, user: admin, name: 'Comercial')
    proposta = create_crm_stage(account: conta, pipeline: funil, name: 'Proposta enviada', position: 1)
    card!(conta, funil, novo, 'Pedro Lima', status: :won, value_cents: 120_000)
    card!(conta, funil, proposta, 'Maria Souza').update!(updated_at: 20.days.ago)
    card!(conta, funil, novo, 'João Alves')
  end

  def card!(conta, funil, etapa, nome, **extras)
    contato = conta.contacts.create!(name: nome, email: "#{SecureRandom.hex(4)}@exemplo.com")
    conta.crm_cards.create!(pipeline: funil, stage: etapa, contact: contato, title: nome, **extras)
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: contas.values.map { |item| item[:conta].id }).sum(:cost_estimate).to_f
  end

  # O Guia semeado já tem a instrução com a camada; a variante sem camada volta a geral. O frescor do Guia não olha a
  # instrução (só a base e o estado canônico), então ele segue pronto nas duas.
  def instrucao!(conta, variante)
    agente = Autonomia::Guide::Seed.ready_agent_for(conta) || raise('Guia não está pronto')
    texto = variante == :com_camada ? Autonomia::Guide::Seed.instrucao_para(conta) : Autonomia::Guide::Seed.instrucao_para
    agente.update!(instruction: texto)
  end

  def perguntar(item, pergunta)
    Autonomia::Guide::Chat.new(account: item[:conta], user: item[:admin], message: pergunta[:texto], history: []).perform
  end

  def julgar(conta, perfil, pergunta, resposta)
    texto = "Tipo da conta e palavras dele: #{AvaliacaoDoVocabulario::VOCABULARIO_DO_JUIZ.fetch(perfil)}\n\n" \
            "Dados da conta: #{AvaliacaoDoVocabulario::DADOS_DA_CONTA}\n\nPergunta: #{pergunta[:texto]}\n\n" \
            "Resposta do assistente: #{resposta.presence || '(nenhuma resposta)'}"
    cliente = Crm::Ai::ResponsesClient.new(credential: Crm::Ai::CredentialResolver.new(account: conta).resolve,
                                           feature: 'eval_juiz', account: conta)
    raw = cliente.create(model: AvaliacaoDoVocabulario::JUIZ, instructions: AvaliacaoDoVocabulario::INSTRUCAO_DO_JUIZ,
                         input: [Autonomia::Agents::PromptParts::Mensagem.montar('user', texto)],
                         schema: AvaliacaoDoVocabulario::VEREDITO)
    JSON.parse(raw[:text])
  end

  def aprovada?(veredito)
    AvaliacaoDoVocabulario::BONS.all? { |campo| veredito[campo] } &&
      AvaliacaoDoVocabulario::RUINS.none? { |campo| veredito[campo] }
  end

  def rodar(perfil, pergunta, variante, vez)
    item = contas.fetch(perfil)
    antes = custo_ate_agora
    instrucao!(item[:conta], variante)
    resultado = perguntar(item, pergunta)
    veredito = julgar(item[:conta], perfil, pergunta, resultado.text)
    { tipo: perfil, pergunta: pergunta[:letra], variante: variante, execucao: vez, resposta: resultado.text.to_s,
      retido: resultado.text.blank?, veredito: veredito, aprovada: aprovada?(veredito),
      custo_usd: (custo_ate_agora - antes).round(4), custo_acumulado_usd: custo_ate_agora.round(4) }
  end

  def folga
    maior = relatorio.pluck(:custo_usd).max.to_f
    [AvaliacaoDoVocabulario::FOLGA_MINIMA_USD, maior * 2].max
  end

  def lista_do_env(nome)
    ENV.fetch(nome, '').split(',').map(&:strip).compact_blank
  end

  def tipos_escolhidos
    pedidos = lista_do_env('GUIA_VOCABULARIO_EVAL_TIPOS')
    pedidos.empty? ? AvaliacaoDoVocabulario::TIPOS : AvaliacaoDoVocabulario::TIPOS & pedidos
  end

  def perguntas_escolhidas
    pedidas = lista_do_env('GUIA_VOCABULARIO_EVAL_PERGUNTAS')
    return AvaliacaoDoVocabulario::PERGUNTAS if pedidas.empty?

    pedidas.filter_map { |letra| AvaliacaoDoVocabulario::PERGUNTAS.find { |pergunta| pergunta[:letra] == letra } }
  end

  def teto
    pedido = ENV.fetch('GUIA_VOCABULARIO_EVAL_TETO_USD', nil).presence&.to_f
    [pedido || AvaliacaoDoVocabulario::TETO_USD, AvaliacaoDoVocabulario::TETO_USD].min
  end

  # Intercalado: vez × pergunta × tipo × variante. Pergunta com `tipos:` só vai a esses tipos.
  def rodadas
    (1..AvaliacaoDoVocabulario::REPETICOES).to_a.product(perguntas_escolhidas, tipos_escolhidos, AvaliacaoDoVocabulario::VARIANTES)
                                           .select { |_vez, pergunta, perfil, _variante| pergunta.fetch(:tipos, [perfil]).include?(perfil) }
  end

  # O eval grava a chave da OpenAI em InstallationConfig: só no banco de teste.
  def banco_de_teste!
    banco = ActiveRecord::Base.connection.current_database.to_s
    raise "eval só roda no banco de teste (#{banco})" unless Rails.env.test? && banco.start_with?('chatwoot_test')
  end

  def rodar_todas
    rodadas.each do |vez, pergunta, perfil, variante|
      if custo_ate_agora + folga > teto
        pulados << { tipo: perfil, pergunta: pergunta[:letra], variante: variante, execucao: vez }
        next
      end

      relatorio << rodar(perfil, pergunta, variante, vez)
    end
  end

  def placar
    relatorio.group_by { |linha| [linha[:tipo], linha[:variante]] }.map do |(perfil, variante), linhas|
      campos = (AvaliacaoDoVocabulario::BONS + AvaliacaoDoVocabulario::RUINS).index_with do |campo|
        "#{linhas.count { |linha| linha[:veredito][campo] }}/#{linhas.size}"
      end
      { tipo: perfil, variante: variante, aprovadas: "#{linhas.count { |linha| linha[:aprovada] }}/#{linhas.size}",
        retidas: linhas.count { |linha| linha[:retido] }, **campos }
    end
  end

  it 'mede o Guia com a instrução geral contra o Guia com a camada de vocabulário do tipo da conta' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['GUIA_VOCABULARIO_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, GUIA_VOCABULARIO_EVAL=1 e OPENAI_API_KEY' unless ligada

    banco_de_teste!
    expect(rodadas).not_to be_empty, 'nenhuma execução com os filtros pedidos'
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))

    rodar_todas

    destino = ENV.fetch('GUIA_VOCABULARIO_EVAL_SAIDA', nil)
    if destino.present?
      File.write(destino, JSON.pretty_generate(placar: placar, custo_usd: custo_ate_agora.round(4), pulados: pulados,
                                               execucoes: relatorio))
    end
    expect(custo_ate_agora).to be <= teto
    expect(pulados).to be_empty, "teto de custo atingido: #{pulados.size} execuções puladas"
  end
end
