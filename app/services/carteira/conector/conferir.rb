# A busca no conector como a tela lê (E7, #2900): enquanto busca, quantos registros chegaram; depois, o Conferir, com os
# mesmos números do Trazer por PDFs.
#
#   { id:, origem: 'conector', estado: 'lendo' | 'parou', diaria:, porSeguradora: [{ nome:, situacao: }], motivo:, recebidos: }
#   { id:, origem: 'conector', estado: 'lida' | 'trazendo' | 'trazida' | 'desfazendo' | 'desfeita', diaria:, porSeguradora:,
#     seguros:, pessoas:, pessoasNovas:, semTelefone:, jaNaCarteira:, naoDeuParaTrazer:, ignorados:, repetidos:,
#     porTipo: { 'auto' => 3 }, total:, naoDeuPorque: { semDados:, semDocumento:, naoLeu: } }
#
# - `seguros`: os seguros prontos para entrar (os registros da mesma referência, como o endosso, são um seguro só), e
#   `pessoas`, de quantas pessoas. `semTelefone`: quantas dessas pessoas ficam sem telefone (a plataforma não o tem: a
#   pessoa que nasce agora nasce sem). `jaNaCarteira`: dos seguros, quantos já estão na carteira e só são atualizados.
# - `naoDeuParaTrazer`: os registros que não entram: sem referência, sem seguradora ou fim da vigência, sem documento do
#   segurado (nunca se casa pessoa pelo nome), mais os que o conector não conseguiu ler (`ignorados`, também à parte).
# - `naoDeuPorque` (só no Conferir, estado `lida`): o `naoDeuParaTrazer` aberto pelo motivo, para a tela dizer o que
#   fazer. `semDados`: falta dado do seguro no conector (referência, seguradora ou data certa); `semDocumento`: falta o
#   CPF/CNPJ do segurado; `naoLeu`: os `ignorados`. A soma é o `naoDeuParaTrazer`. A busca calculada antes destas
#   contagens não traz o campo, e a tela não mostra motivo nenhum.
# - `repetidos`: os registros que não são seguro a mais: o endosso (e o mesmo registro de novo) de um seguro já contado.
# - `total`: quantos registros o conector disse que havia no período. A conta fecha:
#   seguros + (naoDeuParaTrazer - ignorados) + ignorados + repetidos = total.
# - `porSeguradora`: só as seguradoras com evidência de login faltando (`sem_login`) ou recusado (`pede_login`), do
#   pedido (Carteira::Conector::Pedido). Vazio: nada a avisar.
# - `motivo` (só na busca parada): `agger_pede_login` (o login do Agger foi recusado) ou `agger_falhou`.
#
# OS NÚMEROS DO CONFERIR SÃO CALCULADOS NO JOB (`calcular!`, no fim da busca: Carteira::Conector::Sincronizar) e ficam em
# `totais` (só contagens, com o prefixo CHAVE). A requisição só lê: nada de procurar a pessoa de cada registro dentro dela
# nem segurando a trava do Trazer. Depois do Trazer, os números são os que entraram de fato (Carteira::Conector::Gravar).
class Carteira::Conector::Conferir
  BUSCANDO = %w[lendo parou].freeze
  MOTIVOS = [Carteira::Conector::Sincronizar::PEDE_LOGIN, Carteira::Conector::Sincronizar::FALHOU].freeze
  CHAVE = 'conferir_'.freeze
  TIPO = "#{CHAVE}tipo_".freeze
  NUMEROS = %w[seguros pessoas pessoas_novas sem_telefone ja_na_carteira nao_deu sem_dados sem_documento repetidos prontos].freeze

  def initialize(leitura)
    @leitura = leitura
    @totais = leitura.totais.to_h
  end

  def call
    base = { id: @leitura.id, origem: 'conector', estado: @leitura.estado, diaria: @totais.key?(Carteira::Leitura::DIARIA),
             porSeguradora: por_seguradora }
    return base.merge(motivo: motivo, recebidos: @totais['recebidos'].to_i) if BUSCANDO.include?(@leitura.estado)
    return base.merge(numeros, nao_deu_porque) if @leitura.estado == 'lida'

    base.merge(trazidos)
  end

  # Quantos registros entram ao trazer (Carteira::Conector::Trazer), do que o job calculou.
  def prontos
    numero('prontos')
  end

  # No job: calcula os números do Conferir e guarda em `totais`.
  def calcular!
    contagens = Carteira::Conector::Conferir::Contagem.new(@leitura).call
    @leitura.with_lock do
      totais = @leitura.totais.to_h.reject { |chave, _| chave.start_with?(CHAVE) }
      @leitura.update!(totais: totais.merge(contagens.transform_keys { |chave| "#{CHAVE}#{chave}" }))
    end
  end

  private

  def numero(nome)
    @totais["#{CHAVE}#{nome}"].to_i
  end

  def por_seguradora
    Carteira::Conector::Pedido.new(@leitura).por_seguradora.map { |seguradora| { nome: seguradora['nome'], situacao: seguradora['situacao'] } }
  end

  def motivo
    MOTIVOS.find { |codigo| @totais["motivo_#{codigo}"].to_i.positive? } if @leitura.estado == 'parou'
  end

  def numeros
    { seguros: numero('seguros'), pessoas: numero('pessoas'), pessoasNovas: numero('pessoas_novas'), semTelefone: numero('sem_telefone'),
      jaNaCarteira: numero('ja_na_carteira'), naoDeuParaTrazer: numero('nao_deu') + ignorados, ignorados: ignorados,
      repetidos: numero('repetidos') + @totais['repetidos'].to_i, porTipo: por_tipo, total: @totais['total'].to_i }
  end

  def nao_deu_porque
    return {} unless @totais.key?("#{CHAVE}sem_dados")

    { naoDeuPorque: { semDados: numero('sem_dados'), semDocumento: numero('sem_documento'), naoLeu: ignorados } }
  end

  def trazidos
    { seguros: @totais['seguros'].to_i, pessoas: @totais['pessoas'].to_i, pessoasNovas: @totais['pessoas_novas'].to_i, semTelefone: nil,
      jaNaCarteira: nil, naoDeuParaTrazer: falharam + @totais['nao_entraram'].to_i + ignorados, ignorados: ignorados,
      repetidos: repetidos_trazidos, porTipo: {}, total: @totais['total'].to_i }
  end

  # Depois do Trazer: o mesmo registro de novo na lista, o que não mudou nada no seguro, o substituído pelo endosso mais
  # novo e o segundo registro que caiu no mesmo seguro.
  def repetidos_trazidos
    %w[repetidos iguais substituidos registros_trazidos].sum { |chave| @totais[chave].to_i } - @totais['seguros'].to_i
  end

  def ignorados
    @totais['ignorados'].to_i
  end

  def por_tipo
    @totais.select { |chave, _| chave.start_with?(TIPO) }.transform_keys { |chave| chave.delete_prefix(TIPO) }
  end

  def falharam
    @leitura.itens.where(estado: Carteira::Conector::Ler::FALHOU).count
  end
end
