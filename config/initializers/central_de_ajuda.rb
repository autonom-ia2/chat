# Publica a Central de Ajuda depois de cada deploy: o deploy sobe um Sidekiq novo, e a subida enfileira a
# publicação quando a versão embarcada (lib/central_de_ajuda) ainda não foi publicada. Idempotente; as
# duas instâncias do blue/green enfileiram no máximo uma vez a cada 5 minutos, e o lock do publicador
# deixa só uma publicar.
Sidekiq.configure_server do |config|
  config.on(:startup) { Autonomia::CentralDeAjuda::Publicador.garantir_async }
end
