# Aquece o Guia da Plataforma em todas as contas elegíveis depois de cada deploy (#636), com o
# mesmo padrão da Central de Ajuda (`config/initializers/central_de_ajuda.rb`): a subida do
# Sidekiq novo enfileira o aquecimento, e `Seed.ensure_async_for` (chamado por conta dentro do
# job) deduplica com um cache de 5 minutos — as duas instâncias do blue/green não reembedam a
# mesma conta duas vezes.
Sidekiq.configure_server do |config|
  config.on(:startup) { Autonomia::Guide::WarmUpJob.perform_later }
end
