# "Trazer minha lista" (#2896): a planilha que traz o DDD numa coluna e o número em outra. Antes de a planilha ser lida,
# o DDD é posto na frente do número ("(11) 98765-4321") e a coluna do DDD sai da tabela, para o leitor achar um
# telefone inteiro.
#
# Só junta em dois casos, decididos pelo título das colunas, nunca pelo que os valores parecem:
# - a coluna tem título de DDD: junta com a coluna de telefone mais perto dela (pelo título; a da direita primeiro) ou,
#   sem nenhuma, com a coluna logo à direita;
# - a coluna não tem título, está colada à esquerda de uma coluna com título de telefone e só tem DDDs que existem.
# Coluna com outro título ("Idade") nunca vira DDD. Em cada linha, o DDD só entra se for um dos DDDs do Brasil
# (CampaignImports::PhoneNormalizer::DDDS) e o número tiver 8 ou 9 dígitos: o número que já veio com DDD fica como está,
# e a linha com DDD que não existe segue sem DDD e vira problema de telefone. A célula que parece fórmula (no DDD ou no
# número) nunca é juntada: segue como veio, para a leitura acusar a fórmula.
#
# A junção é a mesma a cada leitura da mesma planilha: os índices das colunas que a tela mostra não mudam.
class ContactImports::Trazer::JuntarDdd
  Resultado = Struct.new(:arquivo, :juntadas, keyword_init: true)
  TITULOS_DE_DDD = ['ddd', 'cod area', 'cod. area', 'codigo de area', 'codigo area', 'cod ddd', 'codigo ddd'].freeze
  TITULOS_DE_TELEFONE = CampaignImports::HeaderMapper::ALIASES.fetch(:phone_number).map do |titulo|
    CampaignImports::HeaderMapper.normalize(titulo)
  end.freeze
  LINHAS_DO_CABECALHO = CampaignImports::HeaderLocator::HEADER_SCAN_LIMIT
  DIGITOS_SEM_DDD = [8, 9].freeze
  DDDS = CampaignImports::PhoneNormalizer::DDDS
  Linha = CampaignImports::Parser::ParsedRow

  # arquivo: CampaignImports::Parser::ParsedFile
  def initialize(arquivo)
    @arquivo = arquivo
  end

  def call
    @juntadas = 0
    tabelas = Array(@arquivo.tables).map { |tabela| juntar(tabela) }
    return Resultado.new(arquivo: @arquivo, juntadas: 0) if tabelas.each_with_index.all? { |tabela, indice| tabela.equal?(@arquivo.tables[indice]) }

    Resultado.new(arquivo: arquivo_com(tabelas), juntadas: @juntadas)
  end

  private

  # Como o leitor de planilhas entrega (CampaignImports::Parser, em CSV e em XLSX): o cabeçalho é a primeira linha da
  # primeira tabela e as linhas são o resto dela.
  def arquivo_com(tabelas)
    primeira = tabelas.first.rows
    @arquivo.class.new(headers: primeira.first&.values || [], rows: primeira.drop(1), format: @arquivo.format, tables: tabelas)
  end

  def juntar(tabela)
    cabecalho = tabela.rows.first(LINHAS_DO_CABECALHO).index { |linha| linha.values.any? { |celula| titulo_conhecido?(celula) } }
    par = cabecalho && par_de_colunas(tabela.rows[cabecalho].values.map { |celula| normalizado(celula) }, tabela.rows.drop(cabecalho + 1))
    return tabela unless par

    linhas = tabela.rows.each_with_index.map { |linha, posicao| sem_a_coluna_do_ddd(linha, par, dados: posicao > cabecalho) }
    tabela.class.new(name: tabela.name, rows: linhas, delimiter: tabela.delimiter)
  end

  # [índice da coluna do DDD, índice da coluna do telefone] ou nil.
  def par_de_colunas(titulos, dados)
    ddd = titulos.index { |titulo| TITULOS_DE_DDD.include?(titulo) }
    telefone = ddd && telefone_perto_de(titulos, ddd)
    return [ddd, telefone] if telefone

    telefone = titulos.each_index.find { |indice| colada_sem_titulo?(titulos, dados, indice) }
    telefone && [telefone - 1, telefone]
  end

  # A coluna deste índice tem título de telefone e, colada à esquerda dela, há uma coluna sem título só com DDDs.
  def colada_sem_titulo?(titulos, dados, indice)
    indice.positive? && TITULOS_DE_TELEFONE.include?(titulos[indice]) && titulos[indice - 1].empty? && so_ddds?(dados, indice - 1)
  end

  def telefone_perto_de(titulos, ddd)
    com_titulo = titulos.each_index.select { |indice| TITULOS_DE_TELEFONE.include?(titulos[indice]) }
    com_titulo.min_by { |indice| [(indice - ddd).abs, indice < ddd ? 1 : 0] } || (ddd + 1 if ddd + 1 < titulos.size)
  end

  def so_ddds?(linhas, coluna)
    valores = linhas.filter_map { |linha| linha.values[coluna].to_s.strip.presence }
    valores.any? && valores.all? { |valor| ddd_de(valor) }
  end

  def sem_a_coluna_do_ddd(linha, par, dados:)
    coluna_do_ddd, coluna_do_telefone = par
    valores = linha.values.dup
    junto = dados && juntado(valores[coluna_do_ddd], valores[coluna_do_telefone])
    if junto
      valores[coluna_do_telefone] = junto
      @juntadas += 1
    end
    valores.delete_at(coluna_do_ddd)
    Linha.new(row_number: linha.row_number, values: valores)
  end

  def juntado(ddd, telefone)
    return if formula?(ddd) || formula?(telefone)

    codigo = ddd_de(ddd)
    "(#{codigo}) #{telefone.to_s.strip}" if codigo && DIGITOS_SEM_DDD.include?(telefone.to_s.delete('^0-9').length)
  end

  def formula?(celula)
    CampaignImports::CsvSanitizer.formula_like?(celula, allow_phone_plus: true)
  end

  # "11", "011" e "(11)" são o DDD 11; o que não é um DDD do Brasil não é DDD.
  def ddd_de(celula)
    digitos = celula.to_s.delete('^0-9').delete_prefix('0')
    digitos if DDDS.include?(digitos)
  end

  def titulo_conhecido?(celula)
    titulo = normalizado(celula)
    TITULOS_DE_DDD.include?(titulo) || TITULOS_DE_TELEFONE.include?(titulo)
  end

  def normalizado(celula)
    CampaignImports::HeaderMapper.normalize(celula)
  end
end
