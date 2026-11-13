# "Trazer minha lista" com seguros (E4, #2897): o seguro de uma linha da planilha vai para a carteira, ligado à pessoa
# da linha. Aqui a linha só é traduzida para a forma do banco (Carteira::Trazer::SeguroLido, com o tipo que a leitura
# decidiu para o ramo: Carteira::Trazer::TipoDoRamo); quem decide se a apólice é nova, a mesma ou o termo novo, e grava
# a história, é o gravador único (Carteira::Guardar), com a origem `planilha`.
#
# Roda dentro da gravação de cada linha (ContactImports::Trazer::DestinosDaLinha#aplicar), no mesmo savepoint dela: se o
# seguro não grava, a linha inteira falha e a gravação segue com as outras. A mesma planilha pode voltar quantas vezes
# for: nada duplica.
#
# A empresa só entra como segurada quando o seguro é empresarial e a gravação ligou a pessoa à empresa DA LINHA (o
# vinculador respondeu `created` ou `reused`). Fora disso o seguro fica só na pessoa.
#
# Nada daqui vai para o log: número, bem e datas só existem no banco.
class Carteira::Trazer::SeguroDaLinha
  ORIGEM = 'planilha'.freeze
  EMPRESARIAL = 'empresarial'.freeze
  DA_LINHA = %i[created reused].freeze

  # nil quando a planilha não traz seguros.
  def self.da(importacao)
    colunas = Carteira::Trazer::ColunasDeSeguro.da(importacao)
    new(importacao, colunas) if colunas
  end

  def initialize(importacao, colunas)
    @colunas = colunas
    @tipos = Carteira::Trazer::TipoDoRamo.new(importacao)
    @gravador = Carteira::Guardar.new(importacao.account, origem: ORIGEM, user: importacao.user, importacao: importacao,
                                                          valores: { arquivo: importacao.source_filename })
  end

  # As colunas (pela chave em extra_values) que são do seguro e não viram informação da pessoa.
  def chaves
    @colunas.chaves
  end

  # valores: as outras colunas da linha (extra_values); empresa: o que o vinculador de empresas respondeu, ou nil.
  # Devolve a apólice da linha (a nova ou a que já existia), ou nil quando a linha não tem um seguro inteiro.
  def gravar(contato, valores, empresa: nil)
    lido = Carteira::Trazer::SeguroLido.call(@colunas.valores(valores))
    return unless lido.completo?

    dados = lido.atributos.merge(tipo: @tipos.de(lido.ramo), ramo_original: lido.ramo)
    @gravador.call(dados, contato: contato, empresa: segurada(dados[:tipo], empresa)).apolice
  end

  private

  def segurada(tipo, vinculo)
    vinculo.company if tipo == EMPRESARIAL && vinculo && DA_LINHA.include?(vinculo.status)
  end
end
