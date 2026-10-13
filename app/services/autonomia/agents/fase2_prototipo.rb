# frozen_string_literal: true

# PROTÓTIPO da Fase 2 dos Agentes (épico #1424, lote 1 de mockups). Liga, numa instalação de desenvolvimento, as telas
# do lote para o Rodrigo aprovar antes da implementação: nicho por conta no super admin (#1429), a permissão
# "Gerenciar ferramentas dos agentes" (#1430), a lista de mudanças do "Mudar conversando" (#1428) e os estados do
# agente (#1366). Desligado por padrão; nenhuma instalação de produção define a ENV. Na implementação, cada tela
# passa para a chave por conta do épico (bit a combinar com a Orquestração, #1322) e este módulo sai.
module Autonomia::Agents::Fase2Prototipo
  ENV_KEY = 'AUTONOMIA_FASE2_PROTOTIPO'

  def self.ativo?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch(ENV_KEY, false)) || false
  end
end
