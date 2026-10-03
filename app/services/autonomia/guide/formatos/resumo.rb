# O formato de uma ação em texto curto, para o modelo (#900).
#
# O JSON inteiro de uma ação como a edição de caixa passa de 10 mil
# caracteres — o canal muda por tipo, e há dezenas de campos. O modelo
# precisa do essencial para acertar de primeira: onde vai o corpo, que campos
# existem, de que tipo, quais são obrigatórios e quais valores valem. Tudo
# cabe num teto: o que não cabe é cortado com aviso, nunca em silêncio.
class Autonomia::Guide::Formatos::Resumo
  TETO = 2500
  TIPOS_SIMPLES = [nil, 'string', 'lista'].freeze
  VALORES_POR_CAMPO = [40, 8].freeze
  TIPOS = {
    'string' => 'texto', 'inteiro' => 'número inteiro', 'numero' => 'número', 'booleano' => 'true/false',
    'json' => 'objeto JSON', 'lista' => 'lista', 'objeto_livre' => 'objeto com chaves livres', 'objeto' => 'objeto',
    'lista_de_objetos' => 'lista de objetos', 'data' => 'data AAAA-MM-DD', 'data_hora' => 'data e hora ISO 8601',
    'hora' => 'hora HH:MM'
  }.freeze
  EXEMPLOS = { 'inteiro' => 1, 'numero' => 1, 'booleano' => true, 'lista' => [], 'objeto_livre' => {}, 'objeto' => {},
               'json' => {}, 'lista_de_objetos' => [] }.freeze

  def initialize(acao, formato)
    @acao = acao
    @formato = formato
  end

  def texto
    VALORES_POR_CAMPO.each do |limite|
      texto = montar(campos(limite))
      return texto if texto.size <= TETO
    end
    cortar(campos(VALORES_POR_CAMPO.last))
  end

  # Um campo só, numa linha: o que a recusa da plataforma junta a cada
  # atributo recusado. Nil para campo que o formato não conhece.
  def campo(nome)
    campo = (@formato['campos'] || {})[nome] || (@formato['fora_do_envelope'] || {})[nome]
    campo && "#{nome}: #{descricao(campo, VALORES_POR_CAMPO.first)}"
  end

  private

  def montar(linhas_de_campos)
    [cabecalho, *aviso, *linhas_de_campos, *exemplo, rodape].compact.join("\n")
  end

  # Corta campos do fim, nunca o envelope, o exemplo e o aviso: sem eles o
  # modelo monta o corpo errado com toda a confiança.
  def cortar(linhas)
    (1...linhas.size).each do |cortadas|
      texto = montar(linhas[0...-cortadas] + ["(mais #{cortadas} linhas cortadas pelo limite de tamanho)"])
      return texto if texto.size <= TETO
    end
    montar([]).first(TETO)
  end

  def cabecalho
    return "Formato de #{@acao}: esta ação não lê corpo; mande o corpo vazio ({})." if @formato['sem_corpo']

    envelope = @formato['envelope']
    return "Formato de #{@acao}: os campos vão soltos na raiz do corpo." unless envelope

    plano = @formato['corpo_plano'] ? ' (soltos na raiz também funciona)' : ''
    soltos = Array(@formato['so_no_envelope']).presence
    restricao = soltos ? " Estes só funcionam dentro de \"#{envelope}\": #{soltos.join(', ')}." : ''
    "Formato de #{@acao}: os campos vão dentro de \"#{envelope}\"#{plano}.#{restricao}"
  end

  def aviso
    return [] if @formato['completo']

    ["Atenção: formato parcial (#{Array(@formato['motivos']).join('; ')}). Campo fora desta lista pode existir."]
  end

  def campos(limite)
    lista = @formato['campos'] || {}
    return [] if lista.empty?

    ['Campos:', *linhas(lista, limite, '- ')]
  end

  def linhas(campos, limite, recuo)
    campos.flat_map do |nome, campo|
      dentro = campo['campos'] || {}
      next ["#{recuo}#{nome}: #{descricao(campo, limite)}; campos: #{dentro.keys.join(', ')}", *por_tipo(campo, recuo)] if simples?(dentro)

      ["#{recuo}#{nome}: #{descricao(campo, limite)}", *linhas(dentro, limite, "  #{recuo}"), *por_tipo(campo, recuo)]
    end
  end

  # Objeto cujos campos de dentro não dizem nada além do nome vai numa linha só.
  def simples?(dentro)
    dentro.any? && dentro.values.all? { |campo| campo.except('tipo').empty? && TIPOS_SIMPLES.include?(campo['tipo']) }
  end

  def descricao(campo, limite)
    partes = [TIPOS.fetch(campo['tipo'], campo['tipo']) || 'valor']
    partes << 'obrigatório' if campo['obrigatorio'] == true
    partes << 'obrigatório em alguns casos' if campo['obrigatorio'] == 'condicional'
    partes << 'não pode ficar vazio' if campo['nao_pode_ficar_vazio']
    partes << valores(campo, limite)
    partes << faixa(campo)
    partes << "padrão #{campo['padrao'].to_json}" if campo.key?('padrao')
    partes << campo['so_se'] if campo['so_se']
    partes.compact_blank.join('; ')
  end

  def valores(campo, limite)
    return campo['um_de_resumo'] if campo['um_de_resumo']

    lista = campo['um_de']
    return unless lista

    mostrados = lista.first(limite).join(', ')
    sobra = lista.size > limite ? " e mais #{lista.size - limite}" : ''
    "um de: #{mostrados}#{sobra}"
  end

  def faixa(campo)
    limites = { 'min' => 'mín.', 'max' => 'máx.', 'maior_que' => 'maior que', 'menor_que' => 'menor que',
                'min_caracteres' => 'mín. caracteres', 'max_caracteres' => 'máx. caracteres' }
    limites.filter_map { |chave, rotulo| "#{rotulo} #{campo[chave]}" if campo.key?(chave) }.join(', ').presence
  end

  def por_tipo(campo, recuo)
    return [] unless campo['por_tipo']

    margem = ' ' * (recuo.size + 2)
    tipos = campo['por_tipo'].map { |classe, campos| "#{margem}#{classe}: #{(campos.keys - ['type']).join(', ')}" }
    ["#{margem}os campos de dentro dependem do #{campo['depende_de']}:", *tipos]
  end

  # Com obrigatório, o exemplo é o corpo mínimo. Sem, o exemplo só mostra o
  # envelope — é ele que o modelo erra quando manda o corpo solto.
  def exemplo
    return [] if @formato['sem_corpo'] || @formato['campos'].blank?

    obrigatorios = @formato['campos'].select { |_nome, campo| campo['obrigatorio'] == true }
    return ["Exemplo mínimo: #{envelopado(obrigatorios).to_json}"] if obrigatorios.any?

    nenhum = if @acao.start_with?('PATCH', 'PUT')
               'Nenhum campo é obrigatório: mande só o que muda.'
             else
               'O modelo não marca campo obrigatório; o servidor ainda pode recusar o que faltar.'
             end
    @formato['envelope'] ? [nenhum, "Exemplo: #{envelopado(@formato['campos'].first(1).to_h).to_json}"] : [nenhum]
  end

  def envelopado(campos)
    corpo = campos.transform_values { |campo| valor_de_exemplo(campo) }
    @formato['envelope'] ? { @formato['envelope'] => corpo } : corpo
  end

  def valor_de_exemplo(campo)
    return campo['um_de'].first if campo['um_de'].present?

    EXEMPLOS.fetch(campo['tipo'], '...')
  end

  def rodape
    'Mande só estes nomes: campo desconhecido é ignorado pela plataforma sem aviso.' unless @formato['sem_corpo']
  end
end
