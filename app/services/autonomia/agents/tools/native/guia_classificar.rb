# O Guia classificando muitos itens de uma vez com o Jev (#858): "desses contatos, quais vieram do
# formulário do site?", ou testar a pergunta de um Decisor antes de salvá-lo.
#
# O Jev é uma peça que o Guia usa, não um sistema à parte: a mesma pergunta de múltipla escolha do
# Decisor, montada na hora, sobre textos ou sobre registros que o Guia JÁ LEU neste turno (conversa,
# contato, card) — o mesmo controle de "id lido" de `executar_acao`. Nada é gravado; o resultado é uma
# estimativa com certeza, e agir em cima dele passa pelo desfazer/confirmação de sempre.
#
# O texto de cada item é DADO: o estado mandado ao Jev diz isso, e o contato nunca leva e-mail nem
# telefone. Nenhuma expressão regular: quem entende o texto é o Jev.
class Autonomia::Agents::Tools::Native::GuiaClassificar < Autonomia::Agents::Tools::Native::Base
  MAX_ITENS = 50
  OPCOES = (2..8)
  MAX_PERGUNTA = 1_000
  # O que o Jev lê de cada registro. Nunca e-mail ou telefone (`Decisores::Estado`).
  LEITURAS = {
    'conversa' => %w[mensagens_recentes conversa contato],
    'contato' => %w[contato empresa mensagens_recentes conversa],
    'card' => %w[card contato empresa mensagens_recentes]
  }.freeze

  class << self
    def slug
      'classificar_com_jev'
    end

    def description
      'Classifica muitos itens de uma vez (até 50) numa pergunta de múltipla escolha, rápido e barato, pelo ' \
        'Jev. Use para "desses contatos, quais…" e para testar a pergunta de um Decisor antes de salvá-lo. ' \
        'Cada item é um texto ou um registro que você JÁ LEU neste turno com ler_da_conta (conversa, contato, ' \
        'card). Devolve a escolha e a certeza de cada item: é estimativa. Não muda nada na conta; agir em ' \
        'cima do resultado continua com executar_acao ou propor_acao.'
    end

    def params
      [
        { 'name' => 'pergunta', 'type' => 'string', 'description' => 'A pergunta, como a pessoa faria.' },
        { 'name' => 'opcoes', 'type' => 'array',
          'description' => 'De 2 a 8 respostas possíveis, cada uma com chave curta e descrição do que conta como ela.',
          'items' => { 'properties' => [
            { 'name' => 'chave', 'type' => 'string' }, { 'name' => 'descricao', 'type' => 'string' }
          ] } },
        { 'name' => 'itens', 'type' => 'array',
          'description' => 'Até 50. Cada item é {texto} OU {recurso, id}: recurso é conversa (id = o número da ' \
                           'conversa), contato ou card, com o id que veio da leitura.',
          'items' => { 'properties' => [
            { 'name' => 'texto', 'type' => 'string', 'required' => false },
            { 'name' => 'recurso', 'type' => 'string', 'enum' => LEITURAS.keys, 'required' => false },
            { 'name' => 'id', 'type' => 'string', 'required' => false }
          ] } }
      ]
    end

    # Sem a chave do Jev a ferramenta só falharia: melhor não oferecer.
    def available_for?(_agent)
      TypesafeAi::Config.configured?
    end
  end

  def call
    return 'Não consigo classificar agora porque não sei quem está pedindo.' if @operador.nil?

    recusa = recusa_dos_parametros || recusa_de_leitura
    return recusa if recusa
    return 'Não classifiquei: a conta atingiu o limite mensal de classificações. Diga isso à pessoa.' if cota_esgotada?

    entregar(::Autonomia::Decisores::Classificacao.new(pergunta: pergunta).perform(casos))
  end

  private

  def pergunta
    @pergunta ||= ::Autonomia::Decisor.new(account: @operador.account, nome: self.class.slug,
                                           pergunta: @params['pergunta'].to_s.strip, respostas: opcoes)
  end

  def opcoes
    Array(@params['opcoes']).map { |opcao| { 'chave' => opcao.to_h['chave'].to_s.strip, 'descricao' => opcao.to_h['descricao'].to_s.strip } }
  end

  def itens
    Array(@params['itens']).map { |item| item.to_h.transform_values { |valor| valor.to_s.strip.presence }.compact }
  end

  def recusa_dos_parametros
    return "Não classifiquei: falta a pergunta (até #{MAX_PERGUNTA} caracteres)." unless pergunta.pergunta.length.between?(1, MAX_PERGUNTA)
    return "Não classifiquei: mande de #{OPCOES.min} a #{OPCOES.max} opções, cada uma com chave única e descrição." unless opcoes_validas?

    recusa_dos_itens
  end

  def opcoes_validas?
    chaves = opcoes.pluck('chave')
    OPCOES.cover?(chaves.size) && opcoes.all? { |opcao| opcao.values.all?(&:present?) } && chaves.uniq.size == chaves.size
  end

  def recusa_dos_itens
    return "Não classifiquei: mande de 1 a #{MAX_ITENS} itens; para mais, divida em partes." unless itens.size.between?(1, MAX_ITENS)

    invalido = itens.index { |item| !item_valido?(item) }
    "Não classifiquei: o item #{invalido + 1} precisa de texto OU de recurso (#{LEITURAS.keys.join(', ')}) e id." if invalido
  end

  def item_valido?(item)
    item.key?('texto') ? item.except('texto').empty? : LEITURAS.key?(item['recurso']) && item['id'].present?
  end

  # O id de cada registro tem de ter vindo de uma leitura deste turno, como em executar_acao.
  def recusa_de_leitura
    nao_lidos = itens.filter_map { |item| "#{item['recurso']} #{item['id']}" if item['id'] && @operador.nao_lidos('id' => item['id']).any? }
    return if nao_lidos.empty?

    "Não classifiquei: #{nao_lidos.first(5).join(', ')} não veio de nenhuma leitura da conta nesta conversa. Leia a " \
      'conta com ler_da_conta e use os ids que vieram.'
  end

  def cota_esgotada?
    ::Autonomia::Decisores::Classificacao.cota_esgotada?(@operador.account)
  end

  def casos
    itens.each_with_index.map do |item, indice|
      next { ref: "texto #{indice + 1}", estado: ::Autonomia::Decisores::Estado.new(texto: item['texto'], leituras: []) } if item['texto']

      ref = "#{item['recurso']} #{item['id']}"
      estado = estado_do_registro(item['recurso'], item['id'])
      estado.nil? || estado.vazio? ? { ref: ref, erro: 'nao_encontrado_ou_vazio' } : { ref: ref, estado: estado }
    end
  end

  def estado_do_registro(recurso, id)
    alvo = case recurso
           when 'conversa' then { conversation: conversas.find_by(display_id: id) }
           when 'contato' then contato_com_conversa(id)
           else card_com_conversa(id)
           end
    return if alvo.values.first.nil?

    ::Autonomia::Decisores::Estado.new(**alvo, leituras: LEITURAS.fetch(recurso))
  end

  def contato_com_conversa(id)
    contato = @operador.account.contacts.find_by(id: id)
    { contact: contato, conversation: contato && conversas.where(contact_id: contato.id).reorder(last_activity_at: :desc).first }
  end

  def card_com_conversa(id)
    card = @operador.account.crm_cards.find_by(id: id)
    { card: card, conversation: card&.conversa_em_atendimento }
  end

  # Só as conversas que a pessoa vê na tela.
  def conversas
    @conversas ||= Conversations::PermissionFilterService.new(@operador.account.conversations, @operador.user, @operador.account).perform
  end

  def entregar(resultado)
    parcial = resultado[:fora_do_prazo].positive? ? "Parcial: #{resultado[:fora_do_prazo]} itens ficaram de fora pelo prazo; mande-os de novo. " : ''
    "#{parcial}Estimativa do Jev, com certeza de 0 a 1 por item — confira os de certeza baixa antes de agir. " \
      "#{{ pergunta: pergunta.pergunta, itens: resultado[:itens], resumo: resultado[:resumo] }.to_json}"
  end
end
