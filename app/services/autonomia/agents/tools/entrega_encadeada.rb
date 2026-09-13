# UM TEXTO QUE SÓ PODE SER PUBLICADO DEPOIS DE OUTRA ENTREGA ESTAR NA CONVERSA (fatia 1 do PDF rápido,
# rodada 2, 13/09/2026).
#
# É a forma do fecho de quem tem resultado quando o comparativo desta execução foi aceito para publicação
# e ainda não é uma mensagem (a publicação dele foi adiada). `depois_de` é o token dessa entrega
# (`EntregaPublicada.token_de`). O publicador adia esta forma enquanto não houver mensagem com esse token
# (`AsyncPublisher#esperar?`), até o teto de `AsyncConfig::MAX_DEPENDENCY_DEFERRALS`.
#
# O TOKEN DESTA ENTREGA É O DO TEXTO (`EntregaPublicada.token_de`): é por ele que o fecho idempotente
# (`Tools::Encerramento#fecho_publicado?`) a reconhece.
class Autonomia::Agents::Tools::EntregaEncadeada
  CHAVE = 'encadeada'.freeze

  attr_reader :texto, :depois_de

  # -> a forma, quando `valor` é uma; nil para qualquer outra coisa.
  def self.de(valor)
    return valor if valor.is_a?(self)
    return nil unless valor.is_a?(Hash)

    forma = valor.deep_stringify_keys[CHAVE]
    return nil unless forma.is_a?(Hash)

    new(texto: forma['texto'], depois_de: forma['depois_de'])
  end

  # -> o texto encadeado, serializado, quando há de quem depender; o próprio texto quando não há.
  def self.forma(texto, depois_de:)
    return texto if texto.blank? || depois_de.blank?

    new(texto: texto, depois_de: depois_de).to_h
  end

  def initialize(texto:, depois_de:)
    @texto = texto.to_s.strip
    @depois_de = depois_de.to_s
  end

  def to_h
    { CHAVE => { 'texto' => texto, 'depois_de' => depois_de } }
  end
end
