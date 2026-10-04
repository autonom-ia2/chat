# O corpo que o Guia montou, conferido contra o formato da ação ANTES de chamar
# a plataforma (#900).
#
# Conferir depois não serve: em produção a chave que o `permit` não conhece é
# descartada em silêncio e a resposta é 200. Foi o que aconteceu na conta 18,
# com uma permissão inventada numa função personalizada — a plataforma disse
# "feito" e a função ficou sem a permissão. Aqui o erro vira recusa com o
# motivo e o formato, e o Guia corrige na tentativa seguinte.
#
# Só recusa o que o formato sabe com certeza:
# - chave fora do formato, quando ele é completo (`completo: true`). No formato
#   parcial a chave pode existir sem o gerador ter visto; ali só vira aviso,
#   depois, se ela não aparecer no registro devolvido;
# - valor fora de `um_de` (enum, inclusion). A lista grande demais para o
#   arquivo (`valida_no_servidor`, como o fuso) fica com a plataforma;
# - obrigatório ausente numa criação — só o que o código exige (`params.require`);
#   o que só o modelo exige pode vir da própria action. Com `padrao`, o banco preenche.
#
# Confere o primeiro nível do corpo (dentro do envelope, quando há). Dentro dos
# campos JSON, confere pelo esquema da coluna e pela conta (`por_dentro`, #932):
# cada problema volta com o caminho exato no corpo e os valores que valem.
class Autonomia::Guide::Formatos::Conferencia
  attr_reader :corpo

  def initialize(acao, corpo, conta: nil)
    @acao = acao.to_s
    @conta = conta
    @formato = ::Autonomia::Guide::Formatos.para(@acao)
    @corpo = normalizado(corpo.to_h.deep_stringify_keys)
  end

  # Os campos do corpo num nível só, como a pessoa os leria: envelope aberto.
  def valores
    return @corpo unless envelope && @corpo[envelope].is_a?(Hash)

    @corpo.except(envelope).merge(@corpo[envelope])
  end

  # O que impede a execução, em frases curtas para o modelo. Vazio = segue.
  def problemas
    return [] unless @formato

    @problemas ||= [*sem_corpo, *desconhecidas_recusadas, *fora_da_lista, *faltando, *por_dentro].compact
  end

  # O que está errado DENTRO dos campos JSON: [{ caminho:, motivo:, validos: }].
  def por_dentro
    return [] unless @formato

    dentro.problemas
  end

  # O corpo faz algo sem desfazer, pelo que o esquema marca (`x-sem-volta`)?
  def sem_volta?
    @formato.present? && dentro.sem_volta?
  end

  # A própria conferência, para seguir; ou a recusa, antes de chamar a plataforma.
  def conferida!
    raise ::Autonomia::Guide::Acoes::CorpoForaDoFormato, recusa if recusa

    self
  end

  # A recusa inteira, para o modelo: o que estava errado e o formato da ação.
  # Sem o formato ele erra de novo, com a mesma confiança. Nil = segue.
  def recusa
    return if problemas.empty?

    [
      "Não executei #{@acao}: o corpo não bate com o formato da ação.",
      *problemas.map { |problema| "- #{em_texto(problema)}" },
      ::Autonomia::Guide::Formatos.resumo_para_o_modelo(@acao),
      'Monte o corpo de novo com este formato e tente uma vez.'
    ].compact.join("\n")
  end

  # Chaves enviadas que o formato não lista. No formato parcial não bloqueiam:
  # viram aviso se a plataforma não as devolver no registro.
  def desconhecidas
    return [] unless @formato

    valores.keys - conhecidas
  end

  def completo?
    @formato.present? && @formato['completo'] == true
  end

  private

  def dentro
    @dentro ||= ::Autonomia::Guide::Formatos::PorDentro.new(campos.merge(fora_do_envelope), valores, conta: @conta)
  end

  def em_texto(problema)
    return problema unless problema.is_a?(Hash)

    validos = problema[:validos].present? ? "; vale: #{problema[:validos].join(', ')}" : ''
    "#{problema[:caminho]}: #{problema[:motivo]}#{validos}"
  end

  def envelope
    @formato && @formato['envelope']
  end

  def campos
    (@formato && @formato['campos']) || {}
  end

  def fora_do_envelope
    (@formato && @formato['fora_do_envelope']) || {}
  end

  def conhecidas
    campos.keys | fora_do_envelope.keys
  end

  # Plano ou no envelope, os dois servem: o corpo sai no envelope que a action
  # lê. O `wrap_parameters` só embrulha sozinho as chaves que são coluna do
  # modelo, e campo que não é coluna, mandado solto, sumia. O que a action lê
  # fora do envelope fica também na raiz.
  def normalizado(corpo)
    return desembrulhado(corpo) unless envelope

    dentro = corpo[envelope] || {}
    dentro.is_a?(Hash) ? embrulhado(corpo, dentro) : corpo
  end

  def embrulhado(corpo, dentro)
    soltas = corpo.except(envelope)
    movidas = soltas.select { |chave, _| campos.key?(chave) && !dentro.key?(chave) }
    return corpo if movidas.empty?

    raiz = soltas.reject { |chave, _| movidas.key?(chave) && !fora_do_envelope.key?(chave) }
    raiz.merge(envelope => dentro.merge(movidas))
  end

  # Ação sem envelope que recebeu os campos embrulhados num objeto só
  # ({"inbox": {"name": ...}}): a action lê da raiz, então o objeto se abre.
  def desembrulhado(corpo)
    return corpo unless corpo.size == 1

    chave, dentro = corpo.first
    return corpo if campos.key?(chave) || !dentro.is_a?(Hash) || dentro.empty?

    (dentro.keys - conhecidas).empty? ? dentro : corpo
  end

  def sem_corpo
    return unless @formato['sem_corpo'] && valores.any?

    "esta ação não lê corpo; mande {} (recebeu: #{valores.keys.join(', ')})"
  end

  def desconhecidas_recusadas
    return if !completo? || @formato['sem_corpo'] || desconhecidas.empty?

    "campo que esta ação não tem: #{desconhecidas.join(', ')} (a plataforma descartaria sem avisar)"
  end

  def fora_da_lista
    valores.filter_map do |nome, valor|
      lista = lista_fechada(nome)
      recusados = valor.is_a?(Hash) ? [] : fora_de(lista, valor)
      "#{nome}: #{recusados.join(', ')} não é valor aceito; os aceitos são: #{lista.join(', ')}" if recusados.any?
    end
  end

  def fora_de(lista, valor)
    return [] if lista.empty?

    Array(valor).compact.map(&:to_s).reject { |item| item.blank? || lista.include?(item) }
  end

  # A lista grande demais para o arquivo (o fuso) a plataforma confere sozinha.
  def lista_fechada(nome)
    campo = campos[nome] || {}
    campo['valida_no_servidor'] ? [] : Array(campo['um_de']).map(&:to_s)
  end

  def faltando
    return unless @acao.start_with?('POST ')

    nomes = campos.select { |nome, campo| obrigatorio_sem_padrao?(campo) && ausente?(valores[nome]) }.keys
    "falta o obrigatório: #{nomes.join(', ')}" if nomes.any?
  end

  def obrigatorio_sem_padrao?(campo)
    campo['obrigatorio'] == true && !campo.key?('padrao')
  end

  def ausente?(valor)
    valor.nil? || (valor.is_a?(String) && valor.strip.empty?)
  end
end
