# Os caminhos do "decidir" (F7) conferidos ao salvar: nenhum repetido e cada chave boa. Saiu da Receita, que segue
# chamando por aqui (`CaminhosDoDecidir.problemas`).
class Autonomia::Automacao::CaminhosDoDecidir
  # A chave do caminho sai do nome (minúscula, sem acento) e precisa de pelo menos uma letra.
  LETRAS = ('a'..'z')

  def self.problemas(id, caminhos) = new(id, Array(caminhos)).problemas

  def initialize(id, caminhos)
    @id = id
    @caminhos = caminhos
  end

  def problemas = [*repetidos, *sem_chave_boa]

  private

  # Dois caminhos com a mesma chave ("Cotação" e "cotacao" viram cotacao) ou com o mesmo nome à vista (quem chama a API
  # pode mandar chaves diferentes): uma frase por grupo, com o nome do primeiro, que é o que a pessoa vê.
  def repetidos
    primeiros = @caminhos.each_index.filter_map do |indice|
      @caminhos.first(indice).index { |outro| mesmo_caminho?(outro, @caminhos[indice]) }
    end
    primeiros.uniq.map { |indice| texto(:caminho_repetido, @caminhos[indice]) }
  end

  def mesmo_caminho?(primeiro, outro) = primeiro['chave'] == outro['chave'] || nome_comparavel(primeiro) == nome_comparavel(outro)

  def nome_comparavel(caminho) = caminho['nome'].to_s.strip.downcase

  # A chave "nenhum" é do ramo "nenhum se aplica": um caminho com ela deixaria a resposta da IA e o histórico ambíguos.
  # E a chave precisa de letra: "!!!" vira vazia e "123" fica só com dígitos.
  def sem_chave_boa
    @caminhos.filter_map do |caminho|
      chave = caminho['chave'].to_s
      next texto(:caminho_reservado, caminho) if chave == ::Autonomia::Automacao::Receita::NENHUM

      texto(:caminho_sem_letra, caminho) if chave.each_char.none? { |letra| LETRAS.cover?(letra) }
    end
  end

  def texto(chave, caminho) = I18n.t("autonomia.automacao.receita.#{chave}", passo: @id, nome: caminho['nome'])
end
