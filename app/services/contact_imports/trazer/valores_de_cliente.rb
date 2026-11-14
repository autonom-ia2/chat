require 'json'
require 'stringio'

# "Trazer minha lista" (#2896): os valores da coluna que diz quem é cliente, contados, para a pessoa escolher quais
# querem dizer cliente (Relacionamentos::Trazer::Perguntas). É o único lugar, fora das linhas da importação, onde o
# texto dessas células fica: nada disso vai para options, validation_summary, log ou argumento de job.
#
# Um arquivo pequeno, em JSON, com os TETO valores mais frequentes e a soma dos outros:
#   {"coluna":4,"preenchidas":35,"valores":[{"chave":"9f2c…","valor":"Sim","linhas":12}],"outros":{"valores":7,"linhas":9}}
# - valores iguais depois de agrupados (ContactImports::Trazer::Cliente.agrupado) caem no mesmo grupo; `valor` é a forma
#   mais escrita do grupo, com os espaços arrumados, e `chave` o resumo dele nesta importação e nesta coluna, que é o
#   que a tela devolve;
# - `valor` é só para a pessoa ler e sai com no máximo TETO_DO_VALOR caracteres (o cortado termina em "…"). O grupo e a
#   `chave` são do valor inteiro: dois valores longos que ficam iguais depois do corte continuam sendo dois;
# - do mais frequente ao menos; no empate, a ordem em que aparecem na planilha. A célula vazia não entra em nada;
# - `linhas` conta todas as linhas da planilha, as com problema inclusive: quantas das que ENTRAM viram cliente é outra
#   conta (ContactImports::Trazer::Cliente#quantas).
#
# Quem escreve:
# - a leitura da planilha (ContactImports::Trazer::Validador), a cada passada: apaga o arquivo anterior e conta a
#   coluna que tem o destino "cliente" (`gravar_da_leitura`);
# - a troca que põe uma coluna em "cliente" sem ler a planilha de novo (Relacionamentos::Trazer::TrocarDestino): conta
#   pelas linhas que a leitura já gravou, que guardam o valor de cada coluna (`contar`). O resultado é o mesmo;
# - a coluna que deixa de ser "cliente" leva o arquivo junto (`apagar`).
#
# Some no prazo da planilha original (ContactImports::Trazer::AnexosVencidos). O arquivo velho só é apagado do
# armazenamento depois que a transação termina (ContactImports::Trazer::ApagarAnexo).
#
# Cada objeto baixa o arquivo uma vez, e o que grava passa a ser o que ele lê.
class ContactImports::Trazer::ValoresDeCliente
  NOME = 'valores_cliente.json'.freeze
  TIPO = 'application/json'.freeze
  TETO = 20
  TETO_DO_VALOR = 120
  CORTADO = '…'.freeze
  VAZIA = { 'preenchidas' => 0, 'valores' => [], 'outros' => nil }.freeze
  MARCA = ContactImports::Trazer::Conferencia::CHAVE
  RESPOSTA = ContactImports::Trazer::Cliente::RESPOSTA

  # A célula de uma coluna (pela chave dela em extra_values), para consultar as linhas da importação.
  def self.celula(chave)
    Arel.sql(ActiveRecord::Base.sanitize_sql_array(['extra_values ->> ?', chave]))
  end

  def initialize(importacao)
    @importacao = importacao
  end

  # { 'preenchidas' =>, 'valores' => [...], 'outros' => } da coluna deste índice. Sem arquivo, ou com o arquivo de outra
  # coluna, a contagem vazia.
  def da_coluna(indice)
    guardada['coluna'] == indice ? guardada.slice(*VAZIA.keys) : VAZIA
  end

  # extras: as colunas que não são alvo NESTA leitura ([{ 'index' => 4, 'key' => 'Situação' }]); linhas: as do validador.
  def gravar_da_leitura(extras, linhas)
    destinos = ContactImports::Trazer::Conferencia.new(@importacao).destinos
    coluna = extras.find { |extra| destinos[extra['index'].to_s] == ContactImports::Trazer::Cliente::DESTINO }
    gravar(coluna['index'], linhas.filter_map { |linha| linha[:extra_values][coluna['key']].presence }) if coluna
  end

  def contar(indice)
    chave = Relacionamentos::Trazer::Colunas.new(@importacao).chave_da_extra(indice)
    gravar(indice, @importacao.campaign_import_rows.order(:row_number).pluck(self.class.celula(chave)).compact_blank)
  end

  # A coluna ainda tem, entre os valores mostrados, todos os destas chaves?
  def tem?(indice, chaves)
    (chaves - da_coluna(indice).fetch('valores').pluck('chave')).empty?
  end

  def apagar
    @guardada = {}
    ContactImports::Trazer::ApagarAnexo.call(anexo)
  end

  # As opções da importação depois de uma leitura. A escolha que aponta um valor que a coluna não tem mais deixa de
  # existir, e a pergunta volta sem resposta: nunca se traz com meia escolha.
  def opcoes_depois_da_leitura(opcoes)
    marcas = opcoes[MARCA].to_h
    respostas = marcas['respostas'].to_h
    return opcoes if (Array(respostas.dig(RESPOSTA, 'chaves')) - guardada.fetch('valores', []).pluck('chave')).empty?

    opcoes.merge(MARCA => marcas.merge('respostas' => respostas.except(RESPOSTA)))
  end

  private

  # celulas: o que cada linha tem na coluna, na ordem da planilha, sem as vazias.
  def gravar(indice, celulas)
    grupos = celulas.group_by { |celula| ContactImports::Trazer::Cliente.agrupado(celula) }.values
    grupos = grupos.sort_by.with_index { |formas, ordem| [-formas.size, ordem] }
    @guardada = { 'coluna' => indice, 'preenchidas' => celulas.size, 'valores' => grupos.first(TETO).map { |formas| valor(indice, formas) },
                  'outros' => outros(grupos.drop(TETO)) }
    anexo.attach(io: StringIO.new(JSON.generate(@guardada)), filename: NOME, content_type: TIPO)
  end

  def valor(indice, formas)
    mais_escrita = formas.map(&:squish).tally.max_by { |_forma, vezes| vezes }.first
    { 'chave' => ContactImports::Trazer::Cliente.chave(@importacao.id, indice, mais_escrita),
      'valor' => mais_escrita.truncate(TETO_DO_VALOR, omission: CORTADO), 'linhas' => formas.size }
  end

  def outros(grupos)
    { 'valores' => grupos.size, 'linhas' => grupos.sum(&:size) } if grupos.any?
  end

  def guardada
    @guardada ||= anexo.attached? ? JSON.parse(anexo.download.force_encoding(Encoding::UTF_8)) : {}
  rescue JSON::ParserError
    raise ContactImports::Trazer::ArquivoIlegivel, NOME, cause: nil
  end

  def anexo
    @importacao.public_send(Relacionamentos::Trazer::ArquivoDeProblemas::VALORES_CLIENTE)
  end
end
