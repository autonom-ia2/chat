# De rota do roteador para o recurso que o Guia lê ou muda, e de volta.
#
# Leitura (`Consulta`) e ação (`Acoes`) derivam o catálogo do roteador. As rotas
# de DENTRO da conta (`/api/v1/accounts/:account_id/inboxes`) viram `inboxes`.
# As da PRÓPRIA conta (`/api/v1/accounts/:id` — nome, idioma, fuso) não têm
# `:account_id`, e entravam no catálogo com o caminho inteiro: o Guia montava
# `/api/v1/accounts/16//api/v1/accounts/:id` e "mudar o fuso da conta" falhava
# calado (#593, 22/09/2026). Elas viram o recurso `conta`.
#
# O endereço sai SEMPRE com o id da conta de quem pergunta: nenhum valor vindo
# do modelo escolhe a conta.
module Autonomia::Guide::Rotas
  PREFIXO = '/api/v1/accounts/'.freeze
  DENTRO_DA_CONTA = "#{PREFIXO}:account_id/".freeze
  A_CONTA = "#{PREFIXO}:id".freeze
  CONTA = 'conta'.freeze

  module_function

  # O recurso de uma rota da API, ou nil quando ela não é da conta.
  def recurso(caminho)
    return caminho.delete_prefix(DENTRO_DA_CONTA).presence if caminho.start_with?(DENTRO_DA_CONTA)
    return CONTA if caminho == A_CONTA
    return "#{CONTA}/#{caminho.delete_prefix("#{A_CONTA}/")}" if caminho.start_with?("#{A_CONTA}/")

    nil
  end

  # O endereço real, a partir dos segmentos do recurso já preenchidos.
  def caminho(account_id, segmentos)
    return "#{PREFIXO}#{account_id}/#{segmentos.join('/')}" unless segmentos.first == CONTA

    ["#{PREFIXO}#{account_id}", *segmentos.drop(1)].join('/')
  end
end
