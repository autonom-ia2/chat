# "Marcar como cancelado" e "Voltar a ativo" da gaveta do seguro (E4, #2897). Cancelar não apaga nada: o seguro fica na
# ficha com o selo Cancelado, sai dos grupos de vencimento e a história guarda quem fez. Voltar a ativo devolve o selo
# que a data mandar (Ativo ou Vencido). A apólice fica travada: dois cliques ao mesmo tempo não gravam dois eventos.
#
# Renovação (E5, #2898): cancelar o seguro com a renovação aberta fecha o card dela como perdido, com o motivo
# "cancelou" (Carteira::Renovacao::Fechar#por_cancelamento), na mesma transação. Voltar a ativo NÃO reabre o card: quem
# quiser a renovação de volta desfaz o desfecho na gaveta.
class Carteira::Cancelamento
  def initialize(apolice, user:)
    @apolice = apolice
    @user = user
  end

  def cancelar
    @apolice.with_lock(requires_new: true) do
      recusar('ja_cancelado') if @apolice.cancelado_em
      marcar(Time.current, 'cancelado')
      Carteira::Renovacao::Fechar.new(@apolice, user: @user).por_cancelamento
      @apolice
    end
  end

  def voltar_a_ativo
    @apolice.with_lock(requires_new: true) do
      recusar('nao_cancelado') unless @apolice.cancelado_em
      marcar(nil, 'voltou_a_ativo')
    end
  end

  private

  def marcar(cancelado_em, tipo)
    @apolice.update!(cancelado_em: cancelado_em)
    @apolice.eventos.create!(tipo: tipo, quando: Time.current, user: @user)
    @apolice
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
