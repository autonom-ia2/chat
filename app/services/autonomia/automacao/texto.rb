# O texto de um passo "mensagem" ou "avisar" (#2414 F4): pedaços literais e valores do alvo, montados na hora.
# `["Oi ", {"$valor": "contato.nome"}, ", seu pedido saiu."]`. Não é Liquid: cada valor é um caminho da lista fechada
# de Valores, conferido ao salvar.
class Autonomia::Automacao::Texto
  def self.caminhos(partes)
    Array(partes).filter_map { |parte| parte['$valor'] if parte.is_a?(Hash) }
  end

  def initialize(partes, valores)
    @partes = Array(partes)
    @valores = valores
  end

  # O texto pronto, ou nil quando um valor do alvo está vazio: o passo pula, e nunca sai "Oi , seu pedido saiu". Texto
  # só de espaços volta como está; quem chama pula com o motivo próprio.
  def montar
    lidos = @partes.map { |parte| lido(parte) }
    return if lidos.any?(&:nil?)

    lidos.join
  end

  private

  # O pedaço pronto; nil quando é um valor e ele está vazio.
  def lido(parte)
    return parte unless parte.is_a?(Hash)

    valor = @valores.ler_para_escrever(parte['$valor'])
    valor.is_a?(Array) ? valor.join(', ').presence : valor.presence&.to_s
  end
end
