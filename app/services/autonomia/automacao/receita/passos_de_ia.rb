# Os passos de IA ao salvar (F7; #2608, saiu da Receita): só com a flag da F7; o que fala com gente (escrever ao cliente,
# resumir avisando) também com a da F4. Os caminhos e os campos não repetem, e o extrair só grava onde pode.
class Autonomia::Automacao::Receita::PassosDeIa
  include ::Autonomia::Automacao::Receita::Frase

  # Onde o extrair pode gravar, além dos atributos do contato e da conversa (`<base>.atributos.<chave>`).
  DESTINOS_FIXOS = %w[contato.nome empresa.nome].freeze
  DESTINOS_DE_ATRIBUTO = %w[contato.atributos conversa.atributos].freeze
  # G70: o campo do card no extrair só onde há card (o alvo ou o da conversa), e nunca o que guarda gente
  # (Receita::CAMPOS_DE_GENTE).
  CARD_OU_CONVERSA = %w[Crm::Card Conversation].freeze

  # `contexto`: Receita::Contexto.
  def initialize(contexto)
    @receita = contexto.receita
    @conta = contexto.conta
    @alvo = contexto.alvo
  end

  def problemas(passo)
    id = passo['id']
    [*(::Autonomia::Automacao::Motor.ia?(@conta) ? [] : [texto(:ia_desligada, passo: id)]),
     *(fala_com_gente?(passo) && !::Autonomia::Automacao::Motor.mensagens?(@conta) ? [texto(:passo_desligado, passo: id)] : []),
     *::Autonomia::Automacao::CaminhosDoDecidir.problemas(id, Array(passo['caminhos'])),
     *::Autonomia::Automacao::DecidirDeNovo.problemas_ao_salvar(passo, @receita),
     *repetidos(id, Array(passo['campos']).pluck('chave'), :campo_repetido),
     *Array(passo['campos']).flat_map { |campo| destino_invalido(id, campo['destino']) },
     *destinatarios_de_fora('id' => id, 'para' => avisar_do_resumir(passo))]
  end

  private

  attr_reader :alvo

  # O destino do resumir é "nota" (texto) ou { avisar: ... }; o do escrever é sempre texto.
  def avisar_do_resumir(passo) = passo['destino'].is_a?(Hash) ? passo['destino']['avisar'] : nil

  def fala_com_gente?(passo)
    (passo['tipo'] == 'escrever' && passo['destino'] == 'mensagem') || (passo['tipo'] == 'resumir' && passo['destino'].is_a?(Hash))
  end

  def repetidos(id, chaves, motivo) = chaves.tally.select { |_chave, vezes| vezes > 1 }.keys.map { |chave| texto(motivo, passo: id, chave: chave) }

  def destino_invalido(id, destino)
    return campo_do_card_invalido(id, destino) if ::Autonomia::Automacao::CardDaConversa.destino_do_card?(destino)

    base = DESTINOS_DE_ATRIBUTO.find { |prefixo| destino.to_s.start_with?("#{prefixo}.") }
    valido = DESTINOS_FIXOS.include?(destino) ||
             (base && destino.to_s.length > base.length + 1 && ::Autonomia::Automacao::Valores.atributo_definido?(destino, @conta))
    valido ? [] : [texto(:destino_invalido, passo: id, destino: destino)]
  end

  # G70 (decisão 20): o extrair preenche um campo personalizado do card (o alvo, o card da conversa ou o que a execução
  # criou), nunca o que guarda gente (CAMPOS_DE_GENTE) e só onde há card: gatilho de card ou de conversa.
  def campo_do_card_invalido(id, destino)
    return [texto(:destino_card_sem_card, passo: id)] unless CARD_OU_CONVERSA.include?(alvo)

    campo_do_card_valido?(destino) ? [] : [texto(:destino_invalido, passo: id, destino: destino)]
  end

  # Sem conta (o catálogo), basta a chave; com ela, o campo do card existe e não guarda gente.
  def campo_do_card_valido?(destino)
    _base, chave = ::Autonomia::Automacao::Valores.atributo(destino)
    return chave.present? if @conta.nil?

    campo = chave.present? && @conta.custom_attribute_definitions.find_by(attribute_model: 'card_attribute', attribute_key: chave)
    campo.present? && ::Autonomia::Automacao::Receita::CAMPOS_DE_GENTE.exclude?(campo.attribute_display_type)
  end

  def destinatarios_de_fora(passo)
    ::Autonomia::Automacao::DestinatariosDoAviso.new(@conta, alvo).problemas(passo['id'], passo['para'])
  end
end
