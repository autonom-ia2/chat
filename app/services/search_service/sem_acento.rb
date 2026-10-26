# #2211 — "joao" acha "João". A tabela de letras fica escrita aqui, por extenso, e é a mesma dos índices trigram da
# migration 20261108520000, que usa esta constante. Sem função no banco: o db/schema.rb guarda a expressão do índice como
# está e carrega num banco novo. O spec sem_acento_spec confere que o schema.rb e a constante continuam iguais.
#
# Letras do Latin-1 e do Latin Extended-A que se decompõem numa letra ASCII + acento (NFD). "ø", "ł" e "đ" não se
# decompõem e ficam como estão. Mudar a tabela exige migration nova que recrie os índices: a consulta só usa o índice
# quando a expressão é idêntica.
module SearchService::SemAcento
  COM_ACENTO = 'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿĀ' \
               'āĂăĄąĆćĈĉĊċČčĎďĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĨĩĪīĬĭĮįİĴĵĶķĹĺĻļĽľ' \
               'ŃńŅņŇňŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽž'.freeze
  SEM_ACENTO = 'AAAAAACEEEEIIIINOOOOOUUUUYaaaaaaceeeeiiiinooooouuuuyyA' \
               'aAaAaCcCcCcCcDdEeEeEeEeEeGgGgGgGgHhIiIiIiIiIJjKkLlLlLl' \
               'NnNnNnOoOoOoRrRrRrSsSsSsSsTtTtUuUuUuUuUuUuWwYyYZzZzZz'.freeze

  module_function

  # A expressão do índice, em SQL. `coluna` é SQL escrito no código, nunca texto do usuário.
  def sql(coluna)
    "lower(translate(#{coluna}, '#{COM_ACENTO}', '#{SEM_ACENTO}'))"
  end

  # O mesmo, no Ruby, para o texto buscado.
  def texto(valor)
    valor.to_s.tr(COM_ACENTO, SEM_ACENTO).downcase
  end
end
