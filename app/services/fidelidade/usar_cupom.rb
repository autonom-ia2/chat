# "Marcar como usado" (#3100): no Conferir da aba Cupons ou pela ficha da pessoa. Marca o código como gasto, com quando
# e quem; o desconto a pessoa dá no caixa. Quem pode (decisão D1 do Rodrigo, 23/11): quem pode mexer no contato,
# inclusive o atendente (o controller confere).
#
# Com a linha do código travada: dois toques ao mesmo tempo (ou duas pessoas no balcão) marcam uma vez só, e o segundo
# lê que já estava usado. Marcar de novo o mesmo código não muda nada nem dá erro (`ja_estava`): o toque repetido é o
# mesmo pedido. Código vencido não se marca (Vencido). Cupom pausado não impede: pausar só para de mandar.
class Fidelidade::UsarCupom
  class Vencido < StandardError; end

  Resultado = Data.define(:codigo, :ja_estava)

  def initialize(user, agora: Time.current)
    @user = user
    @agora = agora
  end

  def call(codigo)
    codigo.with_lock do
      estado = codigo.estado(@agora)
      next Resultado.new(codigo: codigo, ja_estava: true) if estado == Fidelidade::CupomCodigo::USADO
      raise Vencido if estado == Fidelidade::CupomCodigo::VENCIDO

      codigo.update!(usado_em: @agora, usado_por: @user, usos: codigo.usos + 1)
      Resultado.new(codigo: codigo, ja_estava: false)
    end
  end
end
