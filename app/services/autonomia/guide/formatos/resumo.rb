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
  # `true` só vem do código (`params.require`); `pelo_modelo` é a presença que
  # o modelo valida, e a action pode preencher.
  OBRIGATORIO = {
    true => 'obrigatório', 'condicional' => 'obrigatório em alguns casos',
    'pelo_modelo' => 'o registro exige, mas a ação pode preencher sozinha'
  }.freeze
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

  # Um campo pelo caminho ("actions", "steps.action_config") e, depois dele, o ramo do esquema
  # ("actions.send_email_to_team"): é o que `formato_da_acao` devolve com `campo:` (#932).
  def do_campo(caminho)
    campo, achado, resto = achar(caminho.to_s.split('.'))
    return "#{@acao} não tem o campo \"#{caminho}\". Campos: #{todos_os_campos.keys.join(', ')}." unless campo
    return "#{achado}: #{descricao(campo, VALORES_POR_CAMPO.first)}" unless campo['esquema']

    esquema = Autonomia::Guide::Formatos::ResumoDoEsquema.new(achado, campo['esquema'])
    return esquema.texto(TETO) if resto.empty?

    esquema.ramo(resto.join('.'), TETO) || "#{achado} não tem o ramo \"#{resto.join('.')}\".\n#{esquema.texto(TETO)}"
  end

  # Um campo só, numa linha: o que a recusa da plataforma junta a cada
  # atributo recusado. Nil para campo que o formato não conhece.
  def campo(nome)
    campo = (@formato['campos'] || {})[nome] || (@formato['fora_do_envelope'] || {})[nome]
    campo && "#{nome}: #{descricao(campo, VALORES_POR_CAMPO.first)}"
  end

  private

  def todos_os_campos
    (@formato['campos'] || {}).merge(@formato['fora_do_envelope'] || {})
  end

  # [campo, caminho até ele, o que sobra do caminho]: desce pelos campos até um que tenha esquema.
  def achar(partes)
    campos = todos_os_campos
    andados = []
    partes.each_with_index do |parte, indice|
      campo = campos[parte]
      return [] unless campo

      andados << parte
      return [campo, andados.join('.'), partes.drop(indice + 1)] if campo['esquema'] || indice == partes.size - 1

      campos = campo['campos'] || {}
    end
    []
  end

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

  def linhas(campos, limite, recuo, prefixo = nil)
    campos.flat_map do |nome, campo|
      caminho = [prefixo, nome].compact.join('.')
      dentro = campo['campos'] || {}
      esquema = do_esquema(campo, caminho, limite, recuo)
      next ["#{recuo}#{nome}: #{descricao(campo, limite)}; campos: #{dentro.keys.join(', ')}", *esquema, *por_tipo(campo, recuo)] if simples?(dentro)

      ["#{recuo}#{nome}: #{descricao(campo, limite)}", *esquema, *linhas(dentro, limite, "  #{recuo}", caminho), *por_tipo(campo, recuo)]
    end
  end

  # O primeiro nível do esquema do campo JSON (#932): valores fechados e o aviso dos ramos.
  def do_esquema(campo, caminho, limite, recuo)
    return [] unless campo['esquema']

    margem = ' ' * (recuo.size + 2)
    Autonomia::Guide::Formatos::ResumoDoEsquema.new(caminho, campo['esquema']).linhas(limite).map { |linha| "#{margem}#{linha}" }
  end

  # Objeto cujos campos de dentro não dizem nada além do nome vai numa linha só.
  def simples?(dentro)
    dentro.any? && dentro.values.all? { |campo| campo.except('tipo').empty? && TIPOS_SIMPLES.include?(campo['tipo']) }
  end

  def descricao(campo, limite)
    partes = [TIPOS.fetch(campo['tipo'], campo['tipo']) || 'valor']
    partes << OBRIGATORIO[campo['obrigatorio']]
    partes << 'não pode ficar vazio' if campo['nao_pode_ficar_vazio']
    partes << valores(campo, limite)
    partes << faixa(campo)
    partes << "padrão #{campo['padrao'].to_json}" if campo.key?('padrao')
    partes.concat(regras_do_texto(campo))
    partes << campo['so_se'] if campo['so_se']
    partes.compact_blank.join('; ')
  end

  def regras_do_texto(campo)
    regras = []
    regras << "o texto tem de casar com a expressão #{campo['padrao_do_texto']}" if campo['padrao_do_texto']
    regras << 'único na conta' if campo['unico']
    regras
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

  # Com obrigatório do código, o exemplo é o corpo mínimo. Sem, o exemplo só
  # mostra o envelope — é ele que o modelo erra quando manda o corpo solto. O
  # exigido só pelo modelo fica fora do mínimo: posto ali, o Guia inventaria o
  # título que o card tiraria do contato.
  def exemplo
    return [] if @formato['sem_corpo'] || @formato['campos'].blank?

    obrigatorios = @formato['campos'].select { |_nome, campo| campo['obrigatorio'] == true }
    return ["Exemplo mínimo: #{envelopado(obrigatorios).to_json}"] if obrigatorios.any?

    nenhum = if @acao.start_with?('PATCH', 'PUT')
               'Nenhum campo é obrigatório: mande só o que muda.'
             else
               'O código da ação não exige campo; o servidor ainda pode recusar o que faltar.'
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
