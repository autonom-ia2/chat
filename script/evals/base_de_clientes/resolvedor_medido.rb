# Guarda a última resposta do Jev (alvo, coluna e confiança) para o relatório da bateria (#1246)
# mostrar por que ele duvidou. Sem resposta (Jev desligado ou com erro), fica nil.
class BaseDeClientesEval::ResolvedorMedido < SimpleDelegator
  attr_reader :ultima

  def resolve(candidate)
    @ultima = nil
    @ultima = __getobj__.resolve(candidate)
  end
end
