# Kit de demo (#2140): lista, uma por linha, as extensões que o db/schema.rb habilita (`enable_extension "x"`).
# O no_m2.sh cria cada uma como postgres antes do schema:load, que roda com a role da demo (sem superuser).
File.foreach(ARGV.fetch(0), encoding: 'UTF-8') do |linha|
  partes = linha.strip.split('"')
  puts partes[1] if partes[0] == 'enable_extension ' && partes[1]
end
