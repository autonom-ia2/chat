namespace :central_de_ajuda do
  # Publica agora, sem esperar a primeira leitura depois do deploy. Mesma rotina do job, idempotente.
  #   bundle exec rails central_de_ajuda:publicar
  desc 'Publica lib/central_de_ajuda no portal "plataforma" da instalação'
  task publicar: :environment do
    resultado = Autonomia::CentralDeAjuda::Publicador.new.publicar!
    next puts('[central_de_ajuda] outra publicação em curso; nada feito') if resultado.nil?

    puts "[central_de_ajuda] #{resultado}"
    resultado.falhas.each { |caminho| puts "  falhou: #{caminho}" }
    exit(1) unless resultado.ok?
  end
end
