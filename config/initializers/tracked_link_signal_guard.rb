# Aviso de clique das páginas (#1011): recusa corpo grande e impede o Rails de interpretar
# (e logar) o corpo antes do controller. Ver lib/middleware/tracked_link_signal_guard.rb.
require Rails.root.join('lib/middleware/tracked_link_signal_guard').to_s

Rails.application.config.middleware.use Middleware::TrackedLinkSignalGuard
