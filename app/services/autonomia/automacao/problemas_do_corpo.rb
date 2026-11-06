# O que o salvar recusa no valor calculado do corpo de uma ação (G16 do #2414), fora do formato da ação (que a Receita
# confere com o exemplo do CampoDaAcao):
# - cada caminho lido passa pela conferência de caminho da Receita (o bloco: desconhecido, fora do alvo, atributo que a
#   conta não tem);
# - a data parte de "hoje" ou de um atributo do tipo data (`data_sem_data`);
# - chave com "$" que não é uma das formas (`forma_desconhecida`);
# - texto montado ou data calculada num campo que nunca os aceitaria (`forma_nao_cabe`).
class Autonomia::Automacao::ProblemasDoCorpo
  def initialize(passo, conta:, &problemas_do_caminho)
    @id = passo['id']
    @acao = passo['acao']
    @corpo = passo['corpo'].to_h
    @conta = conta
    @problemas_do_caminho = problemas_do_caminho
  end

  def problemas
    calculo = ::Autonomia::Automacao::Corpo
    calculo.caminhos(@corpo).flat_map(&@problemas_do_caminho) +
      sem_data.map { |caminho| texto(:data_sem_data, caminho: caminho) } +
      calculo.formas_desconhecidas(@corpo).map { |chave| texto(:forma_desconhecida, chave: chave) } +
      formas_que_nao_cabem
  end

  private

  def sem_data
    ::Autonomia::Automacao::Corpo.datas(@corpo).select do |caminho|
      @problemas_do_caminho.call(caminho).empty? && !::Autonomia::Automacao::Valores.data?(caminho, @conta)
    end
  end

  def formas_que_nao_cabem
    campos = ::Autonomia::Automacao::CampoDaAcao.new(@acao)
    ::Autonomia::Automacao::Corpo.lugares(@corpo).select { |onde, folha| campos.recusa?(onde, folha) }
                                 .map { |onde, _folha| texto(:forma_nao_cabe, campo: campos.nome(onde)) }
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", passo: @id, **valores)
end
