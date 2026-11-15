# A busca no conector como a tela lê (E7, #2900): enquanto busca, o andamento de cada seguradora; depois, o Conferir, com
# os mesmos números do Trazer por PDFs.
#
#   { id:, origem: 'conector', estado: 'lendo' | 'parou', diaria:, porSeguradora: [{ nome:, situacao: }], motivo:, recebidos: }
#   { id:, origem: 'conector', estado: 'lida' | 'trazendo' | 'trazida' | 'desfazendo' | 'desfeita', diaria:, porSeguradora:,
#     seguros:, pessoas:, pessoasNovas:, semTelefone:, naoDeuParaTrazer:, porTipo: { 'auto' => 3 }, total: }
#
# - `seguros`: os seguros prontos para entrar (os registros da mesma referência, como o endosso, são um seguro só), e
#   `pessoas`, de quantas pessoas. `semTelefone`: quantas dessas pessoas ficam sem telefone (a plataforma não o tem: a
#   pessoa que nasce agora nasce sem).
# - `naoDeuParaTrazer`: os registros que não entram: sem referência, sem seguradora ou fim da vigência, sem documento do
#   segurado (nunca se casa pessoa pelo nome), mais os que o conector não conseguiu ler (`ignorados`).
# - `total`: quantos registros o conector disse que havia no período.
# - `motivo` (só na busca parada): `agger_pede_login` (o login do Agger foi recusado) ou `agger_falhou`.
# Depois do Trazer, os números são os que entraram de fato (`totais`).
class Carteira::Conector::Conferir
  BUSCANDO = %w[lendo parou].freeze
  MOTIVOS = [Carteira::Conector::Sincronizar::PEDE_LOGIN, Carteira::Conector::Sincronizar::FALHOU].freeze

  def initialize(leitura)
    @leitura = leitura
    @totais = leitura.totais.to_h
    @pessoas = Carteira::Conector::PessoaDoRegistro.new(leitura.account)
  end

  def call
    base = { id: @leitura.id, origem: 'conector', estado: @leitura.estado, diaria: @totais.key?(Carteira::Leitura::DIARIA),
             porSeguradora: por_seguradora }
    return base.merge(motivo: motivo, recebidos: @totais['recebidos'].to_i) if BUSCANDO.include?(@leitura.estado)
    return base.merge(numeros) if @leitura.estado == 'lida'

    base.merge(trazidos)
  end

  # Quantos registros entram ao trazer.
  def prontos
    vistas.count { |vista| vista[:pronto] }
  end

  private

  def por_seguradora
    Carteira::Conector::Pedido.new(@leitura).por_seguradora.map { |seguradora| { nome: seguradora['nome'], situacao: seguradora['situacao'] } }
  end

  def motivo
    MOTIVOS.find { |codigo| @totais["motivo_#{codigo}"].to_i.positive? } if @leitura.estado == 'parou'
  end

  def numeros
    prontas = vistas.select { |vista| vista[:pronto] }
    { seguros: prontas.uniq { |vista| vista[:ref] }.size, **numeros_das_pessoas(prontas),
      naoDeuParaTrazer: falharam + (vistas.size - prontas.size) + @totais['ignorados'].to_i, porTipo: por_tipo(prontas),
      total: @totais['total'].to_i }
  end

  def numeros_das_pessoas(prontas)
    pessoas = prontas.uniq { |vista| vista[:chave] }
    { pessoas: pessoas.size, pessoasNovas: pessoas.count { |vista| vista[:dono].nil? },
      semTelefone: pessoas.count { |vista| vista[:dono].nil? || vista[:dono].pessoa.phone_number.blank? } }
  end

  def trazidos
    { seguros: @totais['seguros'].to_i, pessoas: @totais['pessoas'].to_i, pessoasNovas: @totais['pessoas_novas'].to_i, semTelefone: nil,
      naoDeuParaTrazer: falharam + @totais['nao_entraram'].to_i + @totais['ignorados'].to_i, porTipo: {}, total: @totais['total'].to_i }
  end

  # O tipo de cada seguro, pelo último registro dele (o endosso mais novo).
  def por_tipo(prontas)
    prontas.reverse.uniq { |vista| vista[:ref] }.map { |vista| vista[:lido].certo('tipo') || Carteira::Conector::TiposDoRamo::OUTRO }.tally
  end

  def falharam
    @leitura.itens.where(estado: Carteira::Conector::Ler::FALHOU).count
  end

  def vistas
    @vistas ||= begin
      donos = {}
      @leitura.itens.where(estado: Carteira::Conector::Ler::LIDO).order(:posicao).map { |item| vista(Carteira::ItemLido.new(item), donos) }
    end
  end

  # A pessoa de cada registro, sem criar ninguém: a mesma referência ou o mesmo documento é perguntado uma vez só.
  def vista(lido, donos)
    chave_de_busca = [lido.valor('ref'), lido.certo('segurado_documento')]
    dono = donos.fetch(chave_de_busca) { donos[chave_de_busca] = @pessoas.achar(lido) }
    { lido: lido, ref: lido.valor('ref'), dono: dono, pronto: dono.present? || @pessoas.nasce?(lido),
      chave: dono ? "pessoa:#{dono.pessoa.id}" : "nova:#{lido.certo('segurado_documento')}" }
  end
end
