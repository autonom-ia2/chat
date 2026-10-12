# Avisa na subida do Sidekiq se a produção está sem chaves de criptografia (#1344). Na subida do Sidekiq, e não no
# boot do Rails, para não disparar no `assets:precompile` do build, que roda sem as chaves.
Sidekiq.configure_server do |config|
  config.on(:startup) { EncryptionAlert.check }
end
