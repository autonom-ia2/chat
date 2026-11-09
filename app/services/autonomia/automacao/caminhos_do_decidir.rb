# Os caminhos do "decidir" (F7, #2500) ao salvar: nomes que não repetem e chave boa. Saiu da Receita quando ela passou do
# tamanho, no merge da main com a G49 (#2414).
module Autonomia::Automacao::CaminhosDoDecidir
  # A chave do caminho sai do nome (minúscula, sem acento) e precisa de pelo menos uma letra.
  LETRAS = ('a'..'z')

  module_function

  def problemas(id, caminhos) = [*repetidos(id, caminhos), *sem_chave_boa(id, caminhos)]

  # Dois caminhos com a mesma chave ("Cotação" e "cotacao" viram cotacao) ou com o mesmo nome à vista (quem chama a API
  # pode mandar chaves diferentes): uma frase por grupo, com o nome do primeiro, que é o que a pessoa vê.
  def repetidos(id, caminhos)
    primeiros = caminhos.each_index.filter_map do |indice|
      caminhos.first(indice).index { |outro| mesmo?(outro, caminhos[indice]) }
    end
    primeiros.uniq.map { |indice| texto(:caminho_repetido, passo: id, nome: caminhos[indice]['nome']) }
  end

  def mesmo?(primeiro, outro) = primeiro['chave'] == outro['chave'] || comparavel(primeiro) == comparavel(outro)

  def comparavel(caminho) = caminho['nome'].to_s.strip.downcase

  # A chave "nenhum" é do ramo "nenhum se aplica": um caminho com ela deixaria a resposta da IA e o histórico ambíguos.
  # E a chave precisa de letra: "!!!" vira vazia e "123" fica só com dígitos.
  def sem_chave_boa(id, caminhos)
    caminhos.filter_map do |caminho|
      chave = caminho['chave'].to_s
      next texto(:caminho_reservado, passo: id, nome: caminho['nome']) if chave == ::Autonomia::Automacao::Receita::NENHUM

      texto(:caminho_sem_letra, passo: id, nome: caminho['nome']) if chave.each_char.none? { |letra| LETRAS.cover?(letra) }
    end
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
