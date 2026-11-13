# "Corrigir" da gaveta do seguro (E4, #2897): grava só os campos que a pessoa mudou, deixa na história o antes e o
# depois de cada um e marca o campo como corrigido à mão, para a próxima importação da planilha não desfazer a correção.
# Mandar o mesmo valor não é correção: não grava nem entra na história.
#
# A apólice fica travada do começo ao fim: duas correções ao mesmo tempo não contam a mesma mudança duas vezes. A
# transação é própria (savepoint), para a recusa do índice único não derrubar a de quem chamou. Outra apólice da conta
# com a mesma seguradora, o mesmo número e o mesmo fim é recusada pelo banco, e a recusa vira `apolice_repetida`.
class Carteira::Corrigir
  def initialize(apolice, dados, user:)
    @apolice = apolice
    @dados = dados
    @user = user
  end

  def call
    novos = Carteira::LeituraDoPedido.new(@dados).atributos
    @apolice.with_lock(requires_new: true) { gravar(novos) }
    @apolice
  rescue ActiveRecord::RecordNotUnique
    recusar('apolice_repetida')
  end

  private

  def gravar(novos)
    conferir_vigencia(novos)
    mudancas = mudancas_de(novos)
    return if mudancas.empty?

    campos = mudancas.pluck(:campo)
    @apolice.update!(novos.merge(corrigido_a_mao: @apolice.corrigido_a_mao | campos))
    @apolice.eventos.create!(tipo: 'corrigido', quando: Time.current, user: @user, valores: { campos: campos }, mudancas: mudancas)
  end

  # Com o que já está gravado: quem muda só o fim ainda tem de terminar depois do começo.
  def conferir_vigencia(novos)
    comeca = novos.fetch(:inicio_vigencia, @apolice.inicio_vigencia)
    recusar('termina_antes') if comeca && novos.fetch(:fim_vigencia, @apolice.fim_vigencia) < comeca
  end

  def mudancas_de(novos)
    Carteira::Campos::COLUNAS.filter_map do |campo, coluna|
      next unless novos.key?(coluna)

      antes = Carteira::Campos.guardado(@apolice[coluna])
      depois = Carteira::Campos.guardado(novos[coluna])
      { campo: campo, antes: antes, depois: depois } unless antes == depois
    end
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
