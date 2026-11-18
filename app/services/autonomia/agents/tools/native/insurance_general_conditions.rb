# Consulta às Condições Gerais das seguradoras (a "Mia") — #319, pelo `/perguntar` desde o #3035.
#
# ISTO INVERTE UMA REGRA. A instrução do multicálculo que roda em produção PROÍBE o agente de
# explicar cobertura, e com razão: são seis manuais diferentes num comparativo, e qualquer resposta
# genérica vira promessa errada. A proibição existia porque não havia como consultar o contrato.
#
# Agora há. Com a CG da seguradora certa na mão, a resposta deixa de ser opinião e passa a ser
# leitura de cláusula. O que continua proibido é responder de memória.
#
# Devolve TEXTO, como toda ferramenta nativa. Cada situação da API vira uma orientação diferente,
# porque confundi-las mente para o cliente:
#   - resposta parcial ≠ resposta completa;
#   - "os trechos não decidem" (`insufficient_context`) ≠ "o contrato não cobre";
#   - regras de dois contratos da mesma seguradora ≠ "a regra da seguradora";
#   - produto achado na empresa irmã ≠ produto da empresa que o cliente citou.
#
# A CHAVE É A DA CONTA: a do hook `crm_kanban_ai`, com o endereço da OpenAI (a API da Mia só fala
# com a OpenAI). Sem ela a ferramenta não entra no prompt — nem com a chave da instalação, nem com a
# do servidor da Mia ("Sempre a chave de cada conta. Sempre!", Rodrigo).
class Autonomia::Agents::Tools::Native::InsuranceGeneralConditions < Autonomia::Agents::Tools::Native::Base
  GENERAL_CONDITIONS = Autonomia::Insurance::GeneralConditions::Client

  FAILED = 'A consulta às condições gerais não respondeu agora. Diga ao cliente que vai confirmar com um ' \
           'especialista em vez de responder por conta própria.'.freeze
  # Limite do que um trecho vale. Medido em 04/09/2026: perguntei a cor preferida do presidente da
  # seguradora e a busca voltou `answered` + `grounded: true`, com o nome de um executivo tirado da
  # saudação do manual. `grounded` diz que o texto veio do documento — NÃO diz que a pergunta era
  # sobre o contrato.
  SCOPE_LIMIT = 'Use isto SÓ se a pergunta for sobre cobertura, exclusão, franquia, prazo ou assistência. ' \
                'Se o trecho responde outra coisa (nome de executivo, endereço, texto institucional), NÃO ' \
                'repasse: diga que não é assunto da apólice.'.freeze
  NOT_A_DENIAL = 'Isso NÃO quer dizer que o contrato não cobre: não diga que não cobre. Diga que vai ' \
                 'confirmar com um especialista. NÃO responda de memória.'.freeze
  OUT_OF_SCOPE = 'A pergunta não é sobre as condições gerais de um seguro. Não use esta consulta para ' \
                 'responder; siga a conversa.'.freeze
  # Trecho sem seguradora identificada: não dá para dizer de quem é a regra, então ela não sai.
  WHICH_INSURER = 'A consulta não identificou a seguradora. Pergunte ao cliente de qual seguradora ele está ' \
                  'falando antes de responder.'.freeze
  CATALOG_MAX = 15

  class << self
    # #2918: LÊ (lê as condições gerais). Nas rodadas das prontas, a que escreve roda uma vez por turno.
    def escreve? = false

    def slug
      'consultar_condicoes_gerais'
    end

    def tool_name
      'Condições gerais da seguradora'
    end

    def description
      'Consulta as condições gerais registradas na SUSEP para responder o que uma seguradora ' \
        'cobre, exclui ou condiciona, comparar a mesma regra entre seguradoras ou achar o PDF das ' \
        'condições. Use quando o cliente perguntar sobre cobertura, franquia, carro reserva, ' \
        'assistência, prazo ou exclusão. Informe a seguradora que o cliente citou. Sem seguradora, a ' \
        'consulta só diz quais seguradoras têm aquele seguro registrado na base.'
    end

    # A seguradora é opcional SÓ para o catálogo ("quem tem fiança locatícia?", decisão do Rodrigo em
    # 16/11/2026). Dúvida de cobertura sem seguradora continua pedindo o nome ao cliente: a regra muda
    # de uma para outra, e responder sem dizer de quem é a regra vira promessa errada.
    def params
      [
        { 'name' => 'seguradora', 'type' => 'string', 'required' => false,
          'description' => 'Nome da seguradora, como o cliente falou. Ex.: "Bradesco", "HDI", "Porto". ' \
                           'null só quando o cliente pergunta quais seguradoras têm um seguro. Dúvida de ' \
                           'cobertura sem seguradora: pergunte ao cliente qual é, antes de consultar.' },
        { 'name' => 'pergunta', 'type' => 'string',
          'description' => 'A dúvida do cliente com as palavras dele, em pergunta completa. Se a mensagem ' \
                           'não diz a seguradora ou o seguro (carro, residencial, vida...), junte em frase o ' \
                           'que a conversa já disse. Ex.: "e a franquia?" vira "Qual a franquia do seguro ' \
                           'residencial da Porto?".' }
      ]
    end

    # Sem o módulo de seguros, ou sem a chave da conta, a ferramenta não entra no prompt. NÃO exige
    # conexão pronta com o portal: responder sobre cobertura é útil antes de existir qualquer cotação.
    def available_for?(agent)
      Autonomia::Insurance::Config.enabled?(agent.account) && GENERAL_CONDITIONS.account_key(agent.account).present?
    rescue StandardError
      false
    end
  end

  def call
    return recusar('condicoes_sem_pergunta', 'Informe a dúvida do cliente para eu consultar.', faltando: ['pergunta']) if question.blank?

    describe(client.ask(question: question, api_key: GENERAL_CONDITIONS.account_key(account)))
  rescue GENERAL_CONDITIONS::InsurerNotFound
    # Lacuna de cobertura da base, não falha: a seguradora existe no mundo, só não temos o contrato dela.
    "Não tenho as condições gerais #{insurer.present? ? "da #{insurer}" : 'dessa seguradora'} na base. " \
    'Confirme o nome com o cliente; se estiver certo, diga que vai checar com um especialista.'
  rescue GENERAL_CONDITIONS::Error => e
    # NUNCA ecoar a mensagem crua ao cliente: o modelo lê o código e escala.
    Rails.logger.warn("[autonomia][native_tool] general_conditions failed account=#{account.id} #{e.message}")
    FAILED
  end

  private

  def describe(answer)
    case answer.route
    when 'comparativo' then describe_comparison(answer)
    when 'documentos' then describe_documents(answer)
    when 'catalogo' then describe_catalog(answer)
    else describe_query(answer)
    end
  end

  def describe_query(answer)
    return OUT_OF_SCOPE if answer.status == 'out_of_scope'
    return ask_which_company(answer) if answer.notice['codigo'] == 'produto_em_seguradora_parecida'
    return product_missing(answer) if answer.notice['codigo'] == 'seguradora_sem_o_produto'
    return failed(answer) if answer.status == 'failed'
    return unresolved(answer) unless answer.usable?
    return WHICH_INSURER if answer.insurer.blank?

    # A resposta carrega SEMPRE de qual seguradora é a regra: sem isso o agente cita a cláusula de
    # uma e o cliente entende que vale para todas as opções do comparativo.
    ["Trecho das condições gerais da #{answer.insurer}: #{answer.text}", other_product_note(answer),
     partial_note(answer), contracts_note(answer),
     "#{SCOPE_LIMIT} Ao usar, diga de qual seguradora é a regra e não estenda para as outras do comparativo."]
      .compact.join("\n\n")
  end

  # A API respondeu com outro produto da mesma seguradora; o trecho já começa dizendo isso.
  def other_product_note(answer)
    return unless answer.notice['codigo'] == 'produto_trocado'

    "A regra é do produto #{answer.notice['produto_usado']}, não de #{answer.notice['produto_pedido']}. " \
      'Diga isso ao cliente antes da regra.'
  end

  def product_missing(answer)
    "A base não tem condições gerais de #{answer.notice['produto']} da #{answer.notice['seguradora']}. " \
      'Isso não quer dizer que a seguradora não vende esse seguro. Diga que vai confirmar com um especialista.'
  end

  def partial_note(answer)
    return unless answer.partial?

    'A resposta é PARCIAL: resolve só uma parte da pergunta, e o próprio trecho diz qual parte fica ' \
      'em aberto. Diga o que ficou claro e que a parte em aberto você confirma com um especialista.'
  end

  def contracts_note(answer)
    return if answer.cited.size < 2

    "A resposta junta #{answer.cited.size} contratos diferentes da #{answer.insurer} " \
      "(SUSEP #{answer.cited.join(', ')}), e o trecho diz qual traz cada regra. Não resuma como " \
      'se fosse uma regra só da seguradora: a que vale depende do contrato da apólice.'
  end

  # Marca irmã: o produto está na outra empresa do grupo (ex.: na Mapfre Vida e não na Mapfre
  # Seguros). A API refez a busca na outra empresa e avisa; quem decide qual empresa vale é o cliente.
  def ask_which_company(answer)
    companies = Array(answer.notice['seguradoras_parecidas']).first(3)
    "#{answer.notice['seguradora']} não tem condições gerais de #{answer.notice['produto']} nesta base, " \
      "mas empresas do mesmo grupo têm: #{companies.join(', ')}. Pergunte ao cliente de qual empresa ele " \
      'está falando antes de responder.'
  end

  # Chave recusada, sem saldo ou erro do modelo no meio do pedido: a API responde 200 com `failed`.
  def failed(answer)
    Rails.logger.warn("[autonomia][native_tool] general_conditions failed account=#{account.id} " \
                      "#{answer.warnings.join(',')}")
    FAILED
  end

  # Duas causas MUITO diferentes chegam aqui, e confundi-las mente para o cliente:
  #   - nome não resolveu -> a base pode ter a resposta, só não sabemos de quem;
  #   - nome resolveu e nenhum trecho decide (`insufficient_context`, `unsupported`, ou `answered` sem
  #     âncora) -> lacuna da busca, que NÃO é "o contrato não cobre".
  def unresolved(answer)
    if !answer.resolved && answer.suggestions.any?
      "Não identifiquei a seguradora \"#{insurer.presence || answer.insurer}\". Pergunte ao cliente se é uma destas: " \
        "#{answer.suggestions.first(3).join(', ')}."
    else
      "Não encontrei nas condições gerais da #{answer.insurer.presence || insurer} um trecho que responda " \
        "isso. #{NOT_A_DENIAL}"
    end
  end

  # Cada seguradora do comparativo tem a sua síntese e o seu status: uma resposta boa de uma não
  # cobre a lacuna da outra.
  def describe_comparison(answer)
    lines = answer.comparisons.map { |item| comparison_line(item) } + coverage_lines(answer.coverage)
    return unresolved(answer) if lines.empty?

    "Comparativo das condições gerais, seguradora por seguradora:\n#{lines.join("\n")}\n\n" \
      "#{SCOPE_LIMIT} Cada regra vale só para a seguradora dela."
  end

  def comparison_line(item)
    if item.usable?
      partial = item.partial? ? ' (parcial: a parte em aberto você confirma com um especialista)' : ''
      "- #{item.insurer}: #{item.text}#{partial}"
    elsif item.status == 'failed'
      failed(item)
      "- #{item.insurer}: a consulta não respondeu agora. Confirme com um especialista."
    else
      "- #{item.insurer}: nenhum trecho das condições gerais responde. Não diga que não cobre; " \
        'confirme com um especialista.'
    end
  end

  # O que o comparativo deixou de fora, para o agente não ler a lista como completa.
  def coverage_lines(coverage)
    lines = coverage[:without_documents].map do |name|
      "- #{name}: a base não tem as condições gerais dela para este seguro. Não diga que não cobre nem que não prevê."
    end
    lines << "- Ficaram fora do comparativo: #{coverage[:left_out].join(', ')}." if coverage[:left_out].any?
    lines << '- O comparativo ficou incompleto: nem todas as seguradoras entraram.' if coverage[:truncated]
    lines + coverage[:readings].map { |name, company| "- \"#{name}\" foi lido como #{company}, não o grupo inteiro." }
  end

  # "Quem tem o produto X": os pares seguradora × produto que a base tem. Estar ou não estar aqui diz
  # só o que foi registrado na SUSEP e lido pela base — não o que cada seguradora vende hoje.
  def describe_catalog(answer)
    return 'Não achei esse seguro na base de condições gerais. Diga que vai confirmar com um especialista.' if answer.catalog.empty?

    pairs = answer.catalog.first(CATALOG_MAX).map { |company, product| "#{company} (#{product})" }
    more = answer.catalog.size > CATALOG_MAX ? " e mais #{answer.catalog.size - CATALOG_MAX}" : ''
    "Condições gerais guardadas nesta base: #{pairs.join(', ')}#{more}. A base tem as condições gerais " \
      'guardadas a partir dos registros da SUSEP: não é a lista completa do mercado, não diz o que cada ' \
      'seguradora vende hoje nem com quem a corretora trabalha.'
  end

  # O PDF oficial. Um pedido genérico costuma achar vários contratos da mesma seguradora; qual vale
  # depende da apólice, e mandar o errado é pior do que não mandar.
  def describe_documents(answer)
    docs = answer.documents
    if docs.size == 1
      doc = docs.first
      return 'O documento não tem link na base. Diga que a equipe envia.' if doc.link.blank?

      "Condições gerais da #{doc.insurer}, #{doc.product} (SUSEP #{doc.process}): #{doc.file_name} " \
        "#{doc.link}\nMande o link só se a pessoa pediu o documento."
    elsif docs.any?
      "Há #{docs.size} condições gerais de #{docs.first.product} da #{docs.first.insurer} na base, uma por " \
        'contrato. Qual vale depende da apólice: não mande link; diga que a equipe envia o documento certo.'
    else
      'Não achei o PDF dessas condições gerais na base. Diga que a equipe envia o documento.'
    end
  end

  def client
    @client ||= GENERAL_CONDITIONS.new
  end

  def insurer
    params['seguradora'].to_s.strip
  end

  # A API lê a pergunta inteira e escolhe seguradora e produto. Quem junta o contexto que falta é o
  # modelo, ao escrever a pergunta (ver `params`): colar rótulo repetido pesava na busca por palavra.
  def question
    params['pergunta'].to_s.strip
  end
end
