# A ordem dos nomes de pessoas nas telas do CRM (#1140): como a tela ordena (localeCompare), sem diferença de acento nem
# de maiúsculas ("Érica" antes de "Fábio"), e com desempate por id para nomes iguais ("Ana" e "ana"). Feita em Ruby, e
# não com a collation do Postgres, que muda de um ambiente para outro.
# Duas etapas, letra a letra: a decomposição Unicode (NFKD) tira as marcas de acento ("ệ" vira "e"); depois o
# `transliterate` do ActiveSupport troca as letras latinas sem decomposição ("Ł" vira "L", "ß" vira "ss"). Letra que ele
# não conhece fica como está: sozinho, ele trocaria "Иван" por "????", que passaria na frente de "Ana".
module Crm::OrdemDeNome
  MARCAS_COMBINANTES = (0x0300..0x036F)

  def self.chave(nome, id)
    [sem_acento(nome).downcase, id]
  end

  def self.sem_acento(nome)
    letras = nome.to_s.scrub.unicode_normalize(:nfkd).each_char.reject { |letra| MARCAS_COMBINANTES.cover?(letra.ord) }
    letras.map { |letra| latina(letra) }.join
  end

  def self.latina(letra)
    trocada = ActiveSupport::Inflector.transliterate(letra, '')
    trocada.empty? ? letra : trocada
  end

  private_class_method :sem_acento, :latina
end
