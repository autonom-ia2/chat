# A conferência de números do Guia (#3158, B8a), portada do `Captain::Copilot::NumberCheck`.
#
# Acha os números da resposta que nenhuma ferramenta do turno sustenta. Um número é sustentado quando aparece no
# que as ferramentas devolveram (ou na conversa), ou sai deles por soma, diferença, razão, percentual, variação
# percentual ou conversão de segundos, na precisão que a resposta mostra. O número sustentado passa a valer como
# conhecido, então a resposta pode mostrar a conta que fez.
#
# Nesta fase só REGISTRA: o que achou vai para o diagnóstico do turno (`Registro`) e a resposta não muda. O
# Copilot também não devolve ao modelo: numa repetição sobre respostas guardadas, a conferência apontou mais
# número certo do que errado.
class Autonomia::Guide::NumerosSemFonte
  # Segundos num minuto, numa hora e num dia; horas num dia; dias na semana; e cem, para percentual.
  UNIDADES = [60, 3600, 86_400, 24, 7, 100].freeze
  CONVERSOES = [60, 3600, 86_400].freeze
  # Os pares crescem com o quadrado dos conhecidos, e a conferência roda no fim do turno, antes da resposta sair:
  # somas e razões usam no máximo estes (as unidades primeiro). 60 dá 1.770 pares; o Copilot usava 200 (19.900).
  MAX_PAREADOS = 60
  SEPARADORES = ".,'’ \u00A0\u2009\u202F".freeze

  # Registra no diagnóstico e no log (só a quantidade: o número pode ser de cliente). Nunca levanta: a conferência
  # não pode segurar a resposta. -> [{ numero:, frase: }].
  def self.registrar(texto:, conhecidos:, registro:, account_id:)
    sem_fonte = new(conhecidos).sem_fonte(texto)
    registro&.numeros_sem_fonte(sem_fonte.size)
    Rails.logger.info("[autonomia][guide][numeros] account=#{account_id} sem_fonte=#{sem_fonte.size}") if sem_fonte.any?
    sem_fonte
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][numeros] account=#{account_id} #{e.class}")
    []
  end

  def initialize(textos)
    @textos = Array(textos).map(&:to_s)
  end

  def sem_fonte(rascunho)
    lacunas = []
    Leitor.frases(rascunho).each do |frase|
      Leitor.da_resposta(frase).each do |numero|
        valor = leituras(numero).find { |leitura| sustentado?(leitura) }
        valor ? aprender(valor.to_f) : lacunas << { numero: numero, frase: frase.strip }
      end
    end
    lacunas.uniq { |lacuna| lacuna[:numero] }
  end

  private

  # Montado só quando a resposta tem número. Data, link e referência entram como conhecidos, mas nunca nas
  # contas: os ids e as datas de uma tabela não podem sustentar um percentual inventado.
  def candidatos
    @candidatos || montar_candidatos
  end

  def montar_candidatos
    numeros = @textos.flat_map { |texto| Leitor.da_ferramenta(texto) }
    medidas = (UNIDADES + numeros.select(&:medida).map { |numero| numero.texto.to_f }).uniq
    @pareados = medidas.first(MAX_PAREADOS)
    @indices = {}
    @candidatos = Set.new(numeros.map { |numero| numero.texto.to_f })
    medidas.each { |valor| um(valor) }
    @pareados.combination(2).each { |primeiro, segundo| par(primeiro, segundo) }
    @candidatos
  end

  # Os candidatos arredondados numa precisão, como inteiros (52,27 com uma casa = 523): a conferência de um número
  # é uma busca no conjunto, e não uma volta por todos os candidatos. Montado na primeira vez que a precisão aparece.
  def indice(precisao)
    candidatos
    @indices[precisao] ||= Set.new(@candidatos.map { |candidato| arredondado(candidato, precisao) })
  end

  def arredondado(valor, precisao)
    (valor.round(precisao) * (10**precisao)).round
  end

  # O número da resposta com o último separador como vírgula decimal e, quando os separadores podem agrupar
  # milhar, também como número inteiro (1.899, 1,23,456).
  def leituras(numero)
    *grupos, ultimo = numero.tr(SEPARADORES, ' ').split
    return [ultimo] if grupos.empty?

    decimal = "#{grupos.join}.#{ultimo}"
    milhar = ultimo.size == 3 && grupos.first.size.between?(1, 3) && !grupos.first.start_with?('0') &&
             grupos.drop(1).all? { |grupo| grupo.size.between?(2, 3) }
    milhar ? [grupos.join + ultimo, decimal] : [decimal]
  end

  def sustentado?(mostrado)
    precisao = mostrado.include?('.') ? mostrado.split('.').last.size : 0
    indice(precisao).include?(arredondado(mostrado.to_f, precisao))
  end

  # Todo candidato novo entra também nos índices já montados.
  def adicionar(valor)
    @candidatos << valor
    @indices.each { |precisao, conjunto| conjunto << arredondado(valor, precisao) }
  end

  def aprender(valor)
    um(valor)
    @pareados.each { |outro| par(valor, outro) }
    @pareados << valor
  end

  def um(valor)
    adicionar(valor)
    CONVERSOES.each { |unidade| adicionar(valor / unidade) }
  end

  def par(primeiro, segundo)
    adicionar(primeiro + segundo)
    adicionar((primeiro - segundo).abs)
    [[primeiro, segundo], [segundo, primeiro]].each do |parte, todo|
      next if todo.zero?

      [parte / todo, parte / todo * 100, (parte - todo).abs / todo * 100].each { |valor| adicionar(valor) }
    end
  end
end
