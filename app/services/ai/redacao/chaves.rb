# As chaves do catálogo de campos (`TemplateFields::Catalog`) dentro de um texto, na sintaxe única do fork:
# `{{cliente.primeiro_nome}}`, `{{horario.data_hora}}` (#1354, combinado com a sessão Modelos WhatsApp, #1333). O texto
# guarda sempre a chave; o número `{{1}}` só existe do lado da Meta.
#
# Leitura por `index` de `{{` e `}}`, sem regex: o texto é quebrado em partes de texto fixo e de chave, na ordem.
# Texto com `{{` sem fechar, `}}` sobrando, `{{` dentro de uma chave, chave com espaço (`{{ cliente.nome }}`) ou `}`
# colado depois da chave (`{{a}}}`) é malformado: a chave vai exatamente como no catálogo.
#
#   Ai::Redacao::Chaves.extrair('Oi, {{cliente.primeiro_nome}}! {{horario.data_hora}}')
#   # => ['cliente.primeiro_nome', 'horario.data_hora']
module Ai::Redacao::Chaves
  ABRE = '{{'.freeze
  FECHA = '}}'.freeze

  Parte = Struct.new(:tipo, :valor) do
    def chave?
      tipo == :chave
    end
  end

  module_function

  # As chaves na ordem em que aparecem (com repetição). Texto malformado devolve só as chaves bem fechadas.
  def extrair(texto)
    partes(texto).select(&:chave?).map(&:valor)
  end

  def malformado?(texto)
    !bem_formado?(texto.to_s)
  end

  # [Parte(:texto, 'Oi, '), Parte(:chave, 'cliente.primeiro_nome'), Parte(:texto, '!')]
  def partes(texto)
    texto = texto.to_s
    resultado = []
    posicao = 0
    while (inicio = texto.index(ABRE, posicao))
      fim = texto.index(FECHA, inicio + ABRE.length)
      break if fim.nil?

      resultado << Parte.new(:texto, texto[posicao...inicio]) if inicio > posicao
      resultado << Parte.new(:chave, texto[(inicio + ABRE.length)...fim])
      posicao = fim + FECHA.length
    end
    resultado << Parte.new(:texto, texto[posicao..]) if posicao < texto.length
    resultado
  end

  # Troca cada chave pelo que o bloco devolver (o valor já pronto). O texto fixo fica como está.
  def preencher(texto)
    partes(texto).map { |parte| parte.chave? ? yield(parte.valor).to_s : parte.valor }.join
  end

  def bem_formado?(texto)
    lista = partes(texto)
    lista.each_with_index.all? do |parte, indice|
      next chave_limpa?(parte.valor) if parte.chave?

      texto_limpo?(parte.valor, depois_de_chave: indice.positive? && lista[indice - 1].chave?)
    end
  end

  def texto_limpo?(valor, depois_de_chave:)
    valor.exclude?(ABRE) && valor.exclude?(FECHA) && !(depois_de_chave && valor.start_with?('}'))
  end

  # Sem chave dentro de chave e sem espaço nenhum: `{{ cliente.nome }}` não é a chave do catálogo.
  def chave_limpa?(chave)
    chave.present? && chave.exclude?('{') && chave.exclude?('}') && chave.each_char.none? { |char| char.strip.empty? }
  end
end
