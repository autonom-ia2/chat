# "Trazer minha lista" (#2896): o que o "Desfazer" de uma lista faria agora, em três números para a tela:
#
# - tira: as pessoas que a lista criou e em quem ninguém tocou. Saem da base;
# - ficam: as que a lista criou e que já têm conversa, card, campanha ou recusa (Relacionamentos::Trazer::QuemFica).
#   Ficam como estão;
# - devolve: as pessoas que a conta já tinha e em que ao menos um campo preenchido pela lista volta ao que era (inclusive
#   a marca de cliente). Lista trazida antes de existir a anotação dos campos não tem o que devolver: 0.
#
# Os três grupos não se misturam: quem a lista criou sai ou fica inteira, e só quem já existia tem campo devolvido.
# Nada é gravado. A conta é feita com as mesmas regras do Desfazer, em blocos (os dos campos são maiores aqui:
# Relacionamentos::Trazer::CamposDaLista::BLOCO_DA_PREVIA).
class Relacionamentos::Trazer::PreviaDoDesfazer
  def initialize(importacao)
    @importacao = importacao
  end

  def call
    tira = 0
    ficam = 0
    Relacionamentos::Trazer::QuemFica.new(@importacao).em_blocos do |saem, ficaram|
      tira += saem.size
      ficam += ficaram.size
    end
    { tira: tira, ficam: ficam, devolve: quantas_voltam }
  end

  private

  def quantas_voltam
    pessoas = Set.new
    campos_da_lista = Relacionamentos::Trazer::CamposDaLista
    campos_da_lista.new(@importacao).em_blocos(tamanho: campos_da_lista::BLOCO_DA_PREVIA) do |campos|
      pessoas.merge(campos.select(&:volta?).filter_map(&:pessoa_id))
    end
    pessoas.size
  end
end
