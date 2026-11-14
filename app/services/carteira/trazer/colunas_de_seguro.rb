# "Trazer minha lista" com seguros (E4, #2897): as colunas da planilha que são de seguro. A pessoa responde "esta
# planilha tem seguros?" (`options['trazer']['respostas']['seguros']`) e diz, na tela das colunas, qual coluna é o
# número da apólice, a seguradora, o ramo, o fim e o começo da vigência, o valor e o bem. O destino fica guardado junto
# dos outros da conferência (`options['trazer']['destinos']`, pelo índice da coluna): só índice e código, nunca o texto
# de uma célula.
#
# Só a conta com a carteira (Carteira::Acesso) tem a pergunta e os destinos. Sem a resposta "sim" nada daqui vale: a
# importação segue como a "Trazer minha lista" de sempre.
#
# Sem número, seguradora, ramo e fim não há seguro para gravar (`faltam`): enquanto falta uma dessas colunas as linhas
# não são conferidas como seguro e o "Trazer" é recusado. Cada destino tem uma coluna só.
#
# O documento (CPF ou CNPJ) não é destino: onde ele mora ainda não foi decidido, e a coluna dele segue como informação
# da pessoa, como já era.
class Carteira::Trazer::ColunasDeSeguro
  RESPOSTA = 'seguros'.freeze
  SIM = 'sim'.freeze
  NAO = 'nao'.freeze
  RESPOSTAS = [SIM, NAO].freeze
  PREFIXO = 'seguro_'.freeze
  OBRIGATORIOS = %w[seguro_numero seguro_seguradora seguro_tipo seguro_termina].freeze
  DESTINOS = (OBRIGATORIOS + %w[seguro_comeca seguro_valor seguro_bem]).freeze

  class << self
    def liberada?(importacao)
      Carteira::Acesso.liberada?(importacao.account)
    end

    # A pessoa disse que a planilha tem seguros, numa conta que tem a carteira.
    def com_seguros?(importacao)
      ContactImports::Trazer::Conferencia.new(importacao).respostas[RESPOSTA] == SIM && liberada?(importacao)
    end

    def destino?(destino)
      DESTINOS.include?(destino)
    end

    # destinos: { '4' => 'seguro_numero', '5' => 'cidade' }, como a conferência guarda.
    def faltam(destinos)
      OBRIGATORIOS - destinos.values
    end

    def sem_os_de_seguro(destinos)
      destinos.reject { |_indice, destino| destino?(destino) }
    end

    # As colunas de seguro de uma importação já lida, ou nil quando a planilha não traz seguros.
    def da(importacao)
      return unless com_seguros?(importacao)

      colunas = Relacionamentos::Trazer::Colunas.new(importacao)
      new(DESTINOS.index_with { |destino| colunas.chaves_do_destino(destino).first }.compact)
    end

    # As mesmas, no meio da leitura: as colunas são as que o leitor acabou de achar
    # (extras: [{ 'index' => 4, 'key' => 'Apólice' }]), não as da leitura anterior.
    def da_leitura(importacao, extras)
      return unless com_seguros?(importacao)

      destinos = ContactImports::Trazer::Conferencia.new(importacao).destinos
      new(DESTINOS.index_with { |destino| extras.find { |extra| destinos[extra['index'].to_s] == destino }&.fetch('key') }.compact)
    end
  end

  # chaves: { 'seguro_numero' => 'Apólice' }: o destino e a chave da coluna em `extra_values` de cada linha.
  def initialize(chaves)
    @chaves = chaves
  end

  # As colunas (pela chave em `extra_values`) que são de seguro: não viram informação da pessoa.
  def chaves
    @chaves.values
  end

  def chave(destino)
    @chaves[destino]
  end

  def faltam
    OBRIGATORIOS - @chaves.keys
  end

  def completas?
    faltam.empty?
  end

  # { 'numero' => 'EX-001234', 'termina' => '10/03/2027' }: o que a linha traz em cada coluna de seguro, como veio.
  def valores(extra_values)
    @chaves.to_h { |destino, chave| [destino.delete_prefix(PREFIXO), extra_values.to_h[chave].to_s.squish] }
  end
end
