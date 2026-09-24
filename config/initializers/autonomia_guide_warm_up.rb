# Aquece o Guia da Plataforma nas contas que JÁ o usam, depois de cada deploy (#636, revisão #637),
# com o mesmo padrão da Central de Ajuda (`config/initializers/central_de_ajuda.rb`): a subida do
# Sidekiq novo enfileira o aquecimento. O próprio job (`WarmUpJob`) trava para rodar UMA vez por
# versão do KB — as duas instâncias do blue/green não repetem a varredura.
Sidekiq.configure_server do |config|
  config.on(:startup) { Autonomia::Guide::WarmUpJob.perform_later }
end
