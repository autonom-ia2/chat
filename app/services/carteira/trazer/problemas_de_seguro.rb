# "Trazer minha lista" com seguros (E4, #2897): as linhas da planilha cujo seguro precisa da pessoa.
#
# Na leitura (`marcar`, chamado pelo validador depois de olhar a mesma pessoa em várias linhas), cada linha ganha os
# motivos do que falta no seguro dela (Carteira::Trazer::SeguroLido), e a linha com motivo não entra. Depois, entre as
# linhas boas, a mesma seguradora com o mesmo número no mesmo termo de vigência (Carteira::Termo):
# - igual em tudo (os mesmos dados, a mesma pessoa): é a linha repetida da planilha; a segunda sai e é contada;
# - diferente em alguma coisa: a segunda vira problema (`seguro_duplicado`) e guarda qual é a primeira (`:outra`), para
#   a pessoa escolher com qual fica. O sistema nunca escolhe calado. É o mesmo desenho da linha repetida de pessoa.
# A linha boa que o gravador da carteira recusaria (a apólice que já está guardada em nome de outra pessoa, ou com dois
# termos guardados sem dar para saber qual é o da linha) ganha o motivo dela em Carteira::Trazer::JaNaCarteira.
#
# Para a tela (`pendencia`, `duplicado`): o tipo e o motivo em palavras dela. A linha com problema de seguro não tem
# conserto na tela (só pode ficar de fora, ou a pessoa arruma a planilha e envia de novo), menos a duplicada, em que
# ela escolhe a linha. O texto que veio errado na célula nunca volta.
class Carteira::Trazer::ProblemasDeSeguro
  DUPLICADO = 'seguro_duplicado'.freeze
  TIPO_DUPLICADO = 'duplicado'.freeze
  # O motivo da linha => [o tipo, o motivo] na tela. Na ordem em que valem: o primeiro que a linha tiver decide.
  NA_TELA = {
    'seguro_numero_falta' => %w[numero falta], 'seguro_numero_cientifico' => %w[numero notacao_cientifica],
    'seguro_seguradora_falta' => %w[seguradora falta], 'seguro_termina_falta' => %w[falta_termina falta],
    'seguro_termina_invalida' => %w[falta_termina data_invalida], 'seguro_termina_antes' => %w[falta_termina termina_antes],
    'seguro_comeca_invalida' => %w[comeca data_invalida], 'seguro_valor_invalido' => %w[valor valor_invalido],
    'seguro_de_outra_pessoa' => %w[numero de_outra_pessoa], 'seguro_termo_ambiguo' => %w[falta_termina termo_ambiguo],
    DUPLICADO => [TIPO_DUPLICADO, nil]
  }.freeze
  SEM_CONSERTO = (NA_TELA.values.map(&:first).uniq - [TIPO_DUPLICADO]).freeze
  # O motivo da recusa de quem tenta consertar na tela uma linha que só se arruma na planilha.
  NA_PLANILHA = 'conserto_na_planilha'.freeze
  # O que identifica a apólice, e não o que ela diz: duas linhas com o número escrito de dois jeitos são iguais.
  DA_IDENTIDADE = %i[seguradora numero].freeze
  DA_PESSOA = %i[normalized_phone email].freeze
  Vista = Struct.new(:linha, :lido)

  class << self
    # O que falta no seguro da linha, para a tela, ou nil quando os motivos dela não são de seguro.
    def pendencia(motivos)
      codigo = NA_TELA.keys.find { |motivo| motivos.include?(motivo) }
      return unless codigo

      tipo, motivo = NA_TELA.fetch(codigo)
      Relacionamentos::Trazer::Pendencia::Resultado.new(tipo: tipo, motivo: motivo)
    end

    def sem_conserto?(tipo)
      SEM_CONSERTO.include?(tipo)
    end

    def duplicada?(motivos)
      Array(motivos).include?(DUPLICADO)
    end
  end

  # colunas: Carteira::Trazer::ColunasDeSeguro.
  def initialize(colunas)
    @colunas = colunas
  end

  # linhas: as do validador ({ extra_values:, errors:, ... }), mexidas no lugar. Devolve quantas linhas repetidas saíram.
  def marcar(linhas)
    vistas = {}
    repetidas = Set.new.compare_by_identity
    linhas.each do |linha|
      lido = ler(linha[:extra_values])
      linha[:errors].concat(lido.motivos)
      repetidas << linha if linha[:errors].empty? && repetida?(vistas, linha, lido)
    end
    linhas.reject! { |linha| repetidas.include?(linha) }
    repetidas.size
  end

  # O cartão da linha duplicada: o número e as duas linhas lado a lado. linha, outra: as linhas da importação no banco.
  def duplicado(linha, outra)
    { numero: @colunas.valores(linha.extra_values)['numero'], outraLinha: outra&.row_number,
      duplicadas: [outra, linha].compact.map { |uma| lado(uma) } }
  end

  private

  def ler(extra_values)
    Carteira::Trazer::SeguroLido.call(@colunas.valores(extra_values))
  end

  # Verdadeiro quando a linha é cópia de outra e sai da lista. A que difere fica, como problema.
  def repetida?(vistas, linha, lido)
    do_numero = (vistas[lido.chave] ||= [])
    anterior = do_numero.find { |vista| Carteira::Termo.mesmo?(vista.lido.atributos, lido.atributos) }
    return true if anterior && igual?(anterior, linha, lido)

    anterior ? apontar(linha, anterior.linha) : do_numero << Vista.new(linha, lido)
    false
  end

  def apontar(linha, primeira)
    linha[:errors] << DUPLICADO
    linha[:outra] = primeira
  end

  def igual?(anterior, linha, lido)
    anterior.lido.atributos.except(*DA_IDENTIDADE) == lido.atributos.except(*DA_IDENTIDADE) &&
      Carteira::Trazer::TipoDoRamo.agrupado(anterior.lido.ramo) == Carteira::Trazer::TipoDoRamo.agrupado(lido.ramo) &&
      anterior.linha.values_at(*DA_PESSOA) == linha.values_at(*DA_PESSOA)
  end

  def lado(linha)
    atributos = ler(linha.extra_values).atributos
    { linha: linha.row_number, seguradora: atributos[:seguradora], termina: atributos[:fim_vigencia]&.iso8601,
      valor: Carteira::Campos.em_reais(atributos[:valor_centavos]), bem: atributos[:bem] }
  end
end
