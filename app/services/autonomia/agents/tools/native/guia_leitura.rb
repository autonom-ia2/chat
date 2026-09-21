# O Guia LENDO a conta, por decisão de quem leu a pergunta (issue #568).
#
# Antes disto a leitura era uma ESTEIRA: um modelo escolhia uma rota no escuro,
# o código adivinhava o que encolher, e quem escrevia a resposta recebia um
# pacote pronto que nunca pediu. Não havia volta — nem para pedir a página
# seguinte, nem para pedir outro campo, nem para fazer a segunda leitura de uma
# pergunta que precisa de duas.
#
# Medido em produção em 21/09/2026: a esteira entregou 67 mil caracteres para
# "quantas conversas abertas eu tenho?" e o `gpt-5.6-sol` respondeu *"o que você
# precisa fazer na plataforma?"*. Com os mesmos dados em 3,6 mil, respondeu
# "você tem 47", nas duas execuções. O que quebrou não foi o dado: foi entregar
# tudo de uma vez a quem não pediu.
#
# Aqui quem pede é o modelo, e ele pode pedir de novo.
class Autonomia::Agents::Tools::Native::GuiaLeitura < Autonomia::Agents::Tools::Native::Base
  # Orçamento de UMA leitura. Fica abaixo do teto de saída de ferramenta
  # (`Tools::Bound::MAX_OUTPUT_CHARS`, 8.000) porque estourá-lo corta JSON no
  # meio. É pequeno de propósito: o modelo tem mais rodadas, e uma resposta que
  # ele consegue usar vale mais do que uma resposta grande que ele ignora.
  TETO = 6_000

  class << self
    def slug
      'ler_da_conta'
    end

    def description
      'Lê dados reais da conta de quem está falando com você, com a permissão dela. Use sempre que a ' \
        'pergunta for sobre o que a conta TEM (quantas caixas, quais funis, quais conversas, quem são os ' \
        'agentes). Pode ser chamada várias vezes: leia, olhe o que voltou e leia de novo se precisar de ' \
        'outro recurso, de outra página ou de outros campos.'
    end

    def params
      [
        { 'name' => 'recurso', 'type' => 'string',
          'description' => 'O recurso, em linguagem de rota: "inboxes", "conversations", "crm/pipelines", ' \
                           '"contacts/:id". Use exatamente um dos nomes do catálogo que você recebeu.' },
        # Objeto de chaves livres não existe em strict mode — a OpenAI recusa a
        # chamada inteira com 400 e o agente fica MUDO. Por isso o que varia vem
        # como texto JSON, e o que é fixo vem como campo próprio.
        { 'name' => 'parametros_json', 'type' => 'string', 'required' => false,
          'description' => 'Preenche os ":id" da rota, como objeto JSON. Para "contacts/:id", ' \
                           '{"id":"123"}. Deixe vazio quando a rota não tiver ":".' },
        { 'name' => 'status', 'type' => 'string', 'required' => false,
          'description' => 'Filtra a listagem por situação, quando o recurso aceitar (ex.: "open", "resolved").' },
        { 'name' => 'pagina', 'type' => 'string', 'required' => false,
          'description' => 'Número da página. A lista vem paginada pela plataforma; peça a 2 para ver ' \
                           'o que veio depois da 1.' },
        { 'name' => 'campos', 'type' => 'array', 'items' => 'string', 'required' => false,
          'description' => 'Quais campos de cada item você quer, como vieram no catálogo de campos da ' \
                           'leitura anterior (ex.: "meta.sender.name"). Pedindo poucos campos cabem muito ' \
                           'mais itens na resposta — é assim que se lê uma lista inteira.' }
      ]
    end
  end

  def call
    return recusa_sem_contexto if @operador.nil?

    @operador.consulta.ler(@params['recurso'].to_s, parametros, filtros,
                           campos: campos, teto: TETO)
  end

  private

  # JSON malformado vindo do modelo não pode derrubar o turno: vira hash vazio,
  # e a `Consulta` recusa com "preciso saber qual id" — frase que o modelo lê e
  # trata pedindo o dado à pessoa.
  def parametros
    texto = @params['parametros_json'].to_s.strip
    return {} if texto.blank?

    valores = JSON.parse(texto)
    valores.is_a?(Hash) ? valores : {}
  rescue JSON::ParserError
    {}
  end

  def filtros
    { 'status' => @params['status'], 'page' => @params['pagina'] }.compact_blank
  end

  def campos
    Array(@params['campos']).map(&:to_s).reject(&:blank?).presence
  end

  # Sem saber QUEM está perguntando não dá para ler nada: a leitura sai com a
  # permissão da pessoa, e não existe permissão "do agente". Acontece no Testar
  # e no playground, onde não há ninguém logado. Recusa nomeada, que o modelo lê
  # e trata — nunca um turno morto.
  def recusa_sem_contexto
    'Não consigo ler a conta agora porque não sei quem está perguntando. Responda pelo que você já sabe.'
  end
end
