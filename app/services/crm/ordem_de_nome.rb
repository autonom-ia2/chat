# A ordem dos nomes de pessoas nas telas do CRM (#1140): como a tela ordena (localeCompare), sem diferença de acento nem
# de maiúsculas ("Érica" antes de "Fábio"), e com desempate por id para nomes iguais ("Ana" e "ana"). Feita em Ruby, e
# não com a collation do Postgres, que muda de um ambiente para outro.
module Crm::OrdemDeNome
  def self.chave(nome, id)
    [ActiveSupport::Inflector.transliterate(nome.to_s).downcase, id]
  end
end
