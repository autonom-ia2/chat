# Monta o caminho e o corpo de UM item a partir da receita (#936).
#
# A receita é estrutura, não texto: o valor que muda de item para item é um objeto de uma chave só,
# e este montador percorre o hash trocando cada um pelo valor do item. Nada de interpolar string —
# um nome de contato nunca vira pedaço de comando.
#
#   {"$item": "name"}                                  o campo do item, como a leitura o devolve ("a.b" desce)
#   {"$jev": true}                                     a escolha do Jev para o item (receita com `classificar`)
#   {"$gerar": {"campo": "name", "instrucao": "…"}}    um valor novo, escrito pela IA do cliente a partir do campo
class Autonomia::Guide::Tarefas::Montador
  ITEM = '$item'.freeze
  JEV = '$jev'.freeze
  GERAR = '$gerar'.freeze
  MARCAS = [ITEM, JEV, GERAR].freeze

  # Qual marca o valor é, ou nil quando é valor comum.
  def self.marca(valor)
    return unless valor.is_a?(Hash) && valor.size == 1

    chave = valor.keys.first.to_s
    chave if MARCAS.include?(chave)
  end

  # Cada marca da estrutura, na ordem em que aparece: [[marca, argumento]].
  def self.marcas(valor, achadas = [])
    marca = marca(valor)
    if marca
      achadas << [marca, valor.values.first]
    elsif valor.is_a?(Hash)
      valor.each_value { |item| marcas(item, achadas) }
    elsif valor.is_a?(Array)
      valor.each { |item| marcas(item, achadas) }
    end
    achadas
  end

  # A chave do valor gerado: o mesmo pedido de `$gerar` na receita é o mesmo valor no item.
  def self.chave_de_gerar(argumento)
    JSON.generate(::Autonomia::Guide::Tarefa.canonica(argumento))
  end

  # O valor de um campo do registro: "name", ou "contact.name" para descer.
  def self.campo(registro, caminho)
    caminho.to_s.split('.').reduce(registro) do |atual, parte|
      case atual
      when Hash then atual[parte]
      when Array then atual[Integer(parte, 10, exception: false) || atual.size]
      end
    end
  end

  def initialize(registro:, escolha: nil, gerados: {})
    @registro = registro
    @escolha = escolha
    @gerados = gerados
  end

  def montar(valor)
    case self.class.marca(valor)
    when ITEM then self.class.campo(@registro, valor.values.first)
    when JEV then @escolha
    # Sem o valor gerado, o item não é montado (KeyError): quem chama o pula com o motivo.
    when GERAR then @gerados.fetch(self.class.chave_de_gerar(valor.values.first))
    else montar_estrutura(valor)
    end
  end

  private

  def montar_estrutura(valor)
    case valor
    when Hash then valor.transform_values { |item| montar(item) }
    when Array then valor.map { |item| montar(item) }
    else valor
    end
  end
end
