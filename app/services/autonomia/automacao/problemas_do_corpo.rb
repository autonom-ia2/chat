# O que o salvar recusa no valor calculado do corpo de uma ação (G16 do #2414), fora do formato da ação (que a Receita
# confere com o exemplo do CampoDaAcao):
# - cada caminho lido passa pela conferência de caminho da Receita (o bloco: desconhecido, fora do alvo, atributo que a
#   conta não tem);
# - a data parte de "hoje" ou de um atributo do tipo data (`data_sem_data`);
# - chave com "$" que não é uma das formas (`forma_desconhecida`);
# - texto montado ou data calculada num campo que nunca os aceitaria (`forma_nao_cabe`);
# - #2632: em `custom_attributes.<chave>`, a data calculada só num atributo da conta do tipo data e o texto montado só
#   num de texto ou de link, que também guarda texto (`data_fora_do_atributo`, `texto_fora_do_atributo`). A chave que a
#   conta não tem segue aceita, como na tela: o campo JSON aceita qualquer chave.
class Autonomia::Automacao::ProblemasDoCorpo
  # Os tipos de atributo (attribute_display_type) onde cada forma cabe, e a frase da recusa.
  NO_ATRIBUTO = { '$data' => [%w[date], :data_fora_do_atributo], '$texto' => [%w[text link], :texto_fora_do_atributo] }.freeze

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
    ::Autonomia::Automacao::Corpo.lugares(@corpo).filter_map do |onde, folha|
      campos.recusa?(onde, folha) ? texto(:forma_nao_cabe, campo: campos.nome(onde)) : fora_do_atributo(campos, onde, folha)
    end
  end

  def fora_do_atributo(campos, onde, folha)
    tipos, frase = NO_ATRIBUTO.find { |forma, _regra| folha.key?(forma) }&.last
    tipo = tipos && tipo_do_atributo(campos, onde)
    texto(frase, chave: campos.atributo(onde)) if tipo && tipos.exclude?(tipo)
  end

  # O tipo do atributo da conta que o lugar grava; nil fora de custom_attributes, sem conta (o catálogo) ou com a chave
  # que a conta não tem.
  def tipo_do_atributo(campos, onde)
    chave = campos.atributo(onde)
    return unless chave && campos.modelo && @conta

    @conta.custom_attribute_definitions.find_by(attribute_model: campos.modelo, attribute_key: chave)&.attribute_display_type
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", passo: @id, **valores)
end
