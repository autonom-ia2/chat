# O que o leitor de apólice devolve (E6, #2899). O leitor não grava nada: quem recebe decide o que fazer (mostrar o que
# mudou, pôr no Conferir, chamar Carteira::Guardar).
#
# - `lido?`: o arquivo é uma apólice e foi lido. `campos` traz TODOS os nomes de CAMPOS, cada um com o valor na forma
#   do banco (texto, AAAA-MM-DD, centavos, só dígitos no documento e no telefone) ou nil. nil é "não achei": o leitor
#   nunca chuta. `duvidas` são os nomes dos campos que ficaram sem valor.
# - `a_confirmar`: dos campos que vieram COM valor, os que não podem ser gravados sem uma pessoa confirmar. Telefone e
#   e-mail lidos de PDF nunca são dados por certos: a apólice traz o telefone do corretor ao lado do CPF do segurado,
#   e nenhuma conferência de valor separa um do outro. Quem recebe o resultado (o Conferir, o "o que mudou") mostra
#   esses campos para a pessoa confirmar antes de gravar na ficha. É separado de `duvidas`: dúvida é campo sem valor.
# - `recusa`: por que não leu. `leitura_desligada` (a conta não tem a leitura liberada), `nao_e_apolice` (o arquivo não
#   é uma apólice de seguro) ou `nao_deu_para_ler` (arquivo ilegível, sem texto, conta sem a IA configurada ou falha
#   do modelo; o detalhe fica em `motivo`, que é para registro, não para a tela).
# - `paginas_total` e `paginas_enviadas` (os números das páginas que foram ao modelo): só contagem, podem ir para log
#   e para `totais`.
#
# `campos` é dado de cliente: não vai para log, argumento de job nem cache. O `inspect` não o mostra.
class Carteira::Leitor::Resultado
  DESLIGADA = 'leitura_desligada'.freeze
  NAO_E_APOLICE = 'nao_e_apolice'.freeze
  NAO_DEU = 'nao_deu_para_ler'.freeze
  RECUSAS = [DESLIGADA, NAO_E_APOLICE, NAO_DEU].freeze
  DA_APOLICE = %w[tipo ramo_original seguradora numero inicio_vigencia fim_vigencia valor_centavos bem].freeze
  # `corretora` é a corretora que aparece na apólice (serve ao seguro de outra corretora).
  CAMPOS = (DA_APOLICE + %w[corretora segurado_nome segurado_documento segurado_telefone segurado_email]).freeze
  A_CONFIRMAR = %w[segurado_telefone segurado_email].freeze

  attr_reader :recusa, :motivo, :campos, :paginas_total, :paginas_enviadas

  def self.lido(campos:, paginas_total:, paginas_enviadas:)
    new(campos: campos, paginas_total: paginas_total, paginas_enviadas: paginas_enviadas)
  end

  def self.recusado(recusa, motivo: nil, paginas_total: nil, paginas_enviadas: [])
    raise ArgumentError, 'recusa' unless RECUSAS.include?(recusa)

    new(recusa: recusa, motivo: motivo, paginas_total: paginas_total, paginas_enviadas: paginas_enviadas)
  end

  def initialize(recusa: nil, motivo: nil, campos: {}, paginas_total: nil, paginas_enviadas: [])
    @recusa = recusa
    @motivo = motivo
    @campos = recusa ? {} : CAMPOS.index_with { |campo| campos[campo] }
    @paginas_total = paginas_total
    @paginas_enviadas = paginas_enviadas
  end

  def lido?
    recusa.nil?
  end

  def duvidas
    campos.select { |_campo, valor| valor.nil? }.keys
  end

  def a_confirmar
    campos.slice(*A_CONFIRMAR).compact.keys
  end

  # Os dados da apólice como Carteira::Guardar recebe, com as chaves de comparação.
  def dados_da_apolice
    campos.slice(*DA_APOLICE).symbolize_keys.merge(
      seguradora_chave: Carteira::Chave.seguradora(campos['seguradora']).presence,
      numero_chave: Carteira::Chave.numero(campos['numero']).presence
    )
  end

  def inspect
    "#<#{self.class.name} recusa=#{recusa.inspect} motivo=#{motivo.inspect} duvidas=#{duvidas.size} " \
      "a_confirmar=#{a_confirmar.size} paginas=#{paginas_enviadas.size}/#{paginas_total.inspect}>"
  end
end
