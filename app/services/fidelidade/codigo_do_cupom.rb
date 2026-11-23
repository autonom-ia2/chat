# O código de um cupom para uma pessoa (#3100): "VOLTA-7KD2". O fim é sorteado com SecureRandom num alfabeto sem as
# letras e números que se confundem no balcão (0 e O, 1, I e L): 23 letras e 8 números. Começa com 4 caracteres; se o
# sorteio bate num código que a conta já tem, tenta de novo e, depois de algumas vezes, passa para 5 e para 6.
#
# Um código por pessoa e cupom: mandar de novo reaproveita o que ela já tem. Dois envios ao mesmo tempo para a mesma
# pessoa ficam com o mesmo código: o índice único (cupom, contato) recusa o segundo, e ele lê o que o primeiro gravou.
# Cada tentativa roda num savepoint, para a recusa do índice não estragar a transação de quem chama.
class Fidelidade::CodigoDoCupom
  LETRAS = ([*'A'..'Z'] - %w[I L O] + [*'2'..'9']).freeze
  TAMANHOS = [4, 5, 6].freeze
  TENTATIVAS_POR_TAMANHO = 5
  SEPARADOR = '-'.freeze

  # Nenhum sorteio deu certo em todas as tentativas (a conta teria de ter quase todos os códigos do prefixo).
  class Esgotado < StandardError; end

  def initialize(cupom)
    @cupom = cupom
  end

  # O código da pessoa: o que ela já tem ou um novo, ainda sem `enviado_em` (quem manda marca depois de mandar).
  def para(contato)
    existente(contato) || criar(contato)
  end

  private

  def existente(contato) = Fidelidade::CupomCodigo.find_by(cupom_id: @cupom.id, contact_id: contato.id)

  def criar(contato)
    TAMANHOS.each do |tamanho|
      TENTATIVAS_POR_TAMANHO.times do
        codigo = tentar(contato, sorteado(tamanho))
        return codigo if codigo
      end
    end
    raise Esgotado, "cupom #{@cupom.id}"
  end

  # O código gravado; nil quando o sorteado já existe na conta (outra pessoa tem). Se outro processo gravou o código desta
  # pessoa primeiro, devolve o dele.
  def tentar(contato, texto)
    Fidelidade::CupomCodigo.transaction(requires_new: true) do
      Fidelidade::CupomCodigo.create!(account_id: @cupom.account_id, cupom: @cupom, contact: contato, codigo: texto)
    end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    existente(contato)
  end

  def sorteado(tamanho)
    fim = Array.new(tamanho) { LETRAS[SecureRandom.random_number(LETRAS.size)] }.join
    [@cupom.prefixo, fim].join(SEPARADOR)
  end
end
