# #3082 (PR B) — o que as IAs recebem dos campos personalizados de uma pessoa ou de uma empresa.
#
# - `valores`: o que está gravado, menos os campos apagados (guardados escondidos, Relationships::CamposGuardados) e as
#   chaves internas (#3176, Relationships::ChavesInternas: os ids da WAHA e o controle da Prospecção), que não dizem
#   nada à IA. A chave sem definição que nunca foi campo (gravada por n8n, importação ou API) continua: a ficha também a
#   mostra.
# - `significados`: para cada chave com definição, o nome que a conta deu ao campo e o "Para que serve"
#   (attribute_description), que a tela avisa que a IA lê. Sem isso a IA recebia só a chave crua ("cf_2").
class Relationships::CamposParaIa
  MAX_TEXTO = 300

  def initialize(account)
    @account = account
  end

  def valores(atributos, modelo)
    visiveis = Relationships::ChavesInternas.sem_internas(atributos)
    return visiveis if @account.nil?

    guardadas = chaves_guardadas(modelo)
    visiveis.reject { |chave, _valor| guardadas.include?(chave.to_s) }
  end

  def significados(chaves, modelo)
    return {} if @account.nil? || chaves.empty?

    definicoes(modelo).slice(*chaves.map(&:to_s)).transform_values do |definicao|
      { name: definicao.attribute_display_name.to_s.first(MAX_TEXTO),
        purpose: definicao.attribute_description.to_s.strip.first(MAX_TEXTO).presence }.compact
    end
  end

  # O significado de uma chave só, para quem monta a própria instrução (o extrator do Decisor).
  def significado(chave, modelo)
    significados([chave], modelo)[chave.to_s]
  end

  private

  def definicoes(modelo)
    @definicoes ||= {}
    @definicoes[modelo] ||= @account.custom_attribute_definitions.visiveis.where(attribute_model: modelo).index_by(&:attribute_key)
  end

  def chaves_guardadas(modelo)
    @guardadas ||= {}
    @guardadas[modelo] ||= Relationships::CamposGuardados.new(@account).lista
                                                         .select { |item| item['attribute_model'] == modelo }
                                                         .to_set { |item| item['attribute_key'] }
  end
end
