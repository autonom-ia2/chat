# Bateria de planilhas da base de clientes (#1246): passa cada caso pelo mesmo motor da
# importação de contatos (#1006: Parser + SpreadsheetReader + Jev) e compara com o gabarito.
#
# Sob demanda, nunca no CI: chama o Jev de verdade (custo nosso) e para antes do teto.
#   BASE_CLIENTES_EVAL=1 TYPESAFE_API_KEY=... bundle exec rails runner script/evals/base_de_clientes/rodar.rb
# Variáveis: REPETICOES (padrão 1), CASOS ("c01,c15"), TETO_USD (padrão 2), SAIDA (pasta do relatório),
# SEMENTE (outros dados para os mesmos casos; padrão 1246), CONJUNTO (principal, controle ou todos).
abort 'Defina BASE_CLIENTES_EVAL=1 para rodar a bateria (chama o Jev pago).' unless ENV['BASE_CLIENTES_EVAL'] == '1'
abort 'Defina TYPESAFE_API_KEY.' if ENV['TYPESAFE_API_KEY'].to_s.empty?

module BaseDeClientesEval; end
module BaseDeClientesEval::Casos; end

require_relative 'dados'
BaseDeClientesEval::Dados.semear!(ENV.fetch('SEMENTE', '1246').to_i)
require_relative 'casos_dsl'
require_relative 'casos_simples'
require_relative 'casos_dia_a_dia'
require_relative 'casos_armadilhas'
require_relative 'casos_controle'
require_relative 'arquivo'
require_relative 'avaliacao'
require_relative 'relatorio'
require_relative 'cliente_medido'
require_relative 'resolvedor_medido'
require_relative 'rodada'

BaseDeClientesEval::Rodada.new.executar
