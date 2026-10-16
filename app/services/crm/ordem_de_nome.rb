# A ordem dos nomes de pessoas nas telas do CRM (#1140): como a tela ordena (localeCompare), sem diferença de acento nem
# de maiúsculas ("Érica" antes de "Fábio"), e com desempate por id para nomes iguais ("Ana" e "ana"). Feita em Ruby, e
# não com a collation do Postgres, que muda de um ambiente para outro.
# O acento sai pela decomposição Unicode (NFKD) tirando as marcas combinantes. Diferente do `transliterate` do
# ActiveSupport, que troca por "?" toda letra fora do latim ("Иван" viraria "????" e passaria na frente de "Ana").
module Crm::OrdemDeNome
  MARCAS_COMBINANTES = (0x0300..0x036F)

  def self.chave(nome, id)
    sem_acento = nome.to_s.unicode_normalize(:nfkd).codepoints.reject { |ponto| MARCAS_COMBINANTES.cover?(ponto) }
    [sem_acento.pack('U*').downcase, id]
  end
end
