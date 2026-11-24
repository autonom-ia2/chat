# Completa um seguro com o que o PDF dele diz, SÓ no que está vazio (E8.1 #3043, extraído para o #3175). Quem lê o PDF
# é quem chama (Carteira::Leitor::DoSeguro); aqui só se grava.
#
# - `campos`: os nomes da tela (Carteira::Campos::COLUNAS) que podem ser completados. A coluna de cada um é também o
#   nome do leitor (Carteira::Leitor::Resultado::CAMPOS).
# - Vazio é nulo ou texto em branco; no tipo, também `outro` (o "não sei" de quem classifica o ramo). O tipo `outro` que
#   o PDF diz nunca entra.
# - O campo corrigido à mão (`corrigido_a_mao`) nunca é completado, nem vazio: foi decisão de gente.
# - Com `ramo: true`, o ramo como veio escrito (`ramo_original`) também é completado quando está em branco. Ele não é
#   campo da tela, e por isso não entra na lista do que mudou.
# - Tudo relido com o seguro travado: o que alguém escreveu enquanto o PDF era lido fica. Nunca sobrescreve e nunca
#   toca nas outras colunas.
# - Só o que o leitor deu como certo (`Resultado#campos`): o que ficou "a confirmar" (o valor sem "R$", o telefone e o
#   e-mail do segurado) não entra por aqui.
#
# `call` devolve o que mudou como a história guarda (Carteira::Campos.mudanca: do dado pessoal, só que estava vazio).
class Carteira::Pdf::Completar
  TIPO = 'tipo'.freeze
  OUTRO = 'outro'.freeze
  RAMO = 'ramo_original'.freeze

  def initialize(apolice, campos:, ramo: false)
    @apolice = apolice
    @campos = campos
    @ramo = ramo
  end

  # Algum dos campos está vazio (vale ler o PDF).
  def falta?
    vazios.any? || (@ramo && @apolice[RAMO].blank?)
  end

  # lidos: { nome do leitor => valor na forma do banco }. -> [mudança]
  def call(lidos)
    @apolice.with_lock(requires_new: true) do
      novos = vazios.filter_map { |campo| [campo, lidos[coluna(campo).to_s]] if serve?(campo, lidos[coluna(campo).to_s]) }.to_h
      colunas = novos.transform_keys { |campo| coluna(campo) }.merge(ramo(lidos))
      mudancas = novos.map { |campo, valor| Carteira::Campos.mudanca(campo, Carteira::Campos.guardado(@apolice[coluna(campo)]), valor) }
      @apolice.update!(colunas) if colunas.any?
      mudancas
    end
  end

  private

  def vazios
    @campos.select { |campo| vazio?(campo) }
  end

  def vazio?(campo)
    return false if @apolice.corrigido_a_mao.include?(campo)

    valor = @apolice[coluna(campo)]
    valor.blank? || (campo == TIPO && valor == OUTRO)
  end

  def serve?(campo, valor)
    valor.present? && !(campo == TIPO && valor == OUTRO)
  end

  def ramo(lidos)
    @ramo && @apolice[RAMO].blank? && lidos[RAMO].present? ? { RAMO.to_sym => lidos[RAMO] } : {}
  end

  def coluna(campo)
    Carteira::Campos::COLUNAS.fetch(campo)
  end
end
