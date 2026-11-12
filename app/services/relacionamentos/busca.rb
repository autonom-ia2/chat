# O que a pessoa digitou na busca da Lista de Relacionamentos (#2894), lido como a tela lê
# (relacionamentos/fonte/listaFonte.js): com alguma letra, procura nos textos, sem diferença de acento nem de maiúscula;
# só com número, procura nos dígitos de telefone e documento, com ou sem pontuação. Tudo por método de texto, sem regex.
class Relacionamentos::Busca
  DIGITOS = '0123456789'.freeze

  def initialize(texto)
    @termo = SearchService::SemAcento.texto(texto).strip
  end

  # `textos` e `numeros` são colunas em SQL escritas no código, nunca texto do usuário.
  def aplicar(escopo, textos:, numeros:)
    return escopo if @termo.empty?
    return escopo.where(*nos_textos(textos)) if tem_letra?

    digitos = @termo.delete('^0-9')
    # Sem letra nem número ("---") não acha ninguém, como na tela.
    digitos.empty? ? escopo.where('FALSE') : escopo.where(*nos_digitos(numeros, digitos))
  end

  private

  def tem_letra?
    @termo.each_char.any? { |letra| letra.between?('a', 'z') }
  end

  # A mesma expressão do índice do nome (SearchService::SemAcento), com o termo inteiro como um trecho só.
  def nos_textos(colunas)
    partes = colunas.map { |coluna| SearchService::SemAcento.todas_as_palavras(coluna, [@termo]) }
    [partes.map(&:first).join(' OR '), *partes.flat_map { |parte| parte.drop(1) }]
  end

  def nos_digitos(colunas, digitos)
    contem = "%#{ActiveRecord::Base.sanitize_sql_like(digitos)}%"
    [colunas.map { |coluna| "#{so_digitos(coluna)} LIKE ?" }.join(' OR '), *colunas.map { contem }]
  end

  # Só os dígitos da coluna: o translate de dentro devolve tudo que não é dígito, e o de fora apaga isso.
  def so_digitos(coluna)
    "translate(#{coluna}, translate(#{coluna}, '#{DIGITOS}', ''), '')"
  end
end
