# #2024: a blue aguenta o schema que esta green vai deixar? Roda no deploy, antes de a green existir.
#
# A CI compara as migrations com a main, mas a fila não espera o deploy e o deploy pula SHA superado: a blue pode estar
# vários PRs atrás. Exemplo: o PR 1 anuncia a remoção (ignored_columns e db/retiradas.yml), entra na main e não sobe; o
# PR 2 remove e passa na CI, porque a main já anunciou; os dois sobem juntos e a blue, sem o ignored_columns, perde os
# INSERTs. Aqui vale o schema.rb e o db/retiradas.yml do commit da blue, com a mesma Compatibilidade da CI.
#
# uso: ruby compatibilidade_com_a_blue.rb <schema.rb da blue> <schema.rb deste commit> [db/retiradas.yml da blue]
# Ruby puro, sem o Rails nem gems. Sai 1 com bloqueio, 2 com uso errado.
require 'yaml'

module MigrationsSeguras; end
require_relative '../../lib/migrations_seguras/schema_rb'
require_relative '../../lib/migrations_seguras/compatibilidade'

schema_da_blue, schema_novo, retiradas_da_blue = ARGV
unless schema_da_blue && schema_novo
  warn 'uso: ruby compatibilidade_com_a_blue.rb <schema.rb da blue> <schema.rb deste commit> [db/retiradas.yml da blue]'
  exit 2
end

retiradas = retiradas_da_blue && File.file?(retiradas_da_blue) ? YAML.safe_load_file(retiradas_da_blue) || {} : {}
verificacao = MigrationsSeguras::Compatibilidade.new(
  antes: MigrationsSeguras::SchemaRb.ler(File.read(schema_da_blue)),
  depois: MigrationsSeguras::SchemaRb.ler(File.read(schema_novo)),
  retiradas: retiradas
)

verificacao.avisos.each { |achado| puts "::notice::Schema contra a blue: #{achado}" }
if verificacao.compativel?
  puts "A blue aguenta o schema novo (#{verificacao.avisos.size} aviso(s))."
  exit 0
end

verificacao.bloqueios.each { |achado| puts "::error::A blue não aguenta o schema novo: #{achado}" }
puts 'Nada foi mexido: a green não foi lançada e a blue segue no ar. Ver docs/migrations-em-lote.md (Remover ou renomear).'
exit 1
