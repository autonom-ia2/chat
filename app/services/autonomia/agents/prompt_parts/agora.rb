# DATA E HORA DO TURNO, NO FUSO DA CONTA (#3211, P6). O modelo não sabe que dia é: sem isto ele erra "amanhã", "sexta" e
# data sem ano. O item entra como `developer` logo antes da pergunta (depois do histórico e da memória), então
# instruções + histórico continuam sendo o prefixo estável do cache. Quem decide se entra é o PromptBuilder.
#
# O dia da semana sai de tabela em pt-BR (`strftime('%A')` sairia em inglês). O fuso é o mesmo da memória do turno:
# `Crm::Timezone::Resolver` (conta ou o padrão da instalação).
module Autonomia::Agents::PromptParts::Agora
  DIAS_DA_SEMANA = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze
  FORMATO = '%d/%m/%Y %H:%M'.freeze

  module_function

  # account pode ser nil: cai no fuso padrão. -> String
  def texto(account, agora: Time.current)
    fuso = ::Crm::Timezone::Resolver.new(account: account).name_or_default
    local = agora.in_time_zone(fuso)
    "Agora: #{DIAS_DA_SEMANA[local.wday]}, #{local.strftime(FORMATO)} (fuso da conta: #{fuso})."
  end
end
