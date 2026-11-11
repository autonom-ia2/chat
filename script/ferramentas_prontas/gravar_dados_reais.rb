# #2858 — grava o `dados` REAL de cada fonte grátis das ferramentas prontas (os pedidos, a anonimização e a gravação
# estão em `dados_reais.rb`, ao lado). Sem cache: o `Rails.cache` vira NullStore aqui.
#
# Uso (só no ambiente de teste):
#   RAILS_ENV=test bundle exec rails runner script/ferramentas_prontas/gravar_dados_reais.rb [fonte ...]
# Sem fonte: todas as do CASOS. Com fonte (ex.: ncm compras_governo): só elas. Cada arquivo é reescrito por consulta.
# Fonte sem decisão de anonimização: aborta antes de chamar qualquer fonte.
require_relative 'dados_reais'

abort('rode com RAILS_ENV=test') unless Rails.env.test?
Rails.cache = ActiveSupport::Cache::NullStore.new

begin
  Time.use_zone('America/Sao_Paulo') { DadosReaisDasProntas.rodar(ARGV) }
rescue DadosReaisDasProntas::SemDecisao => e
  abort(e.message)
end
