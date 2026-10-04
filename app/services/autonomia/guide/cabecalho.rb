# O CONTEXTO INTERNO que abre a pergunta do Guia: perfil, tela, registro aberto e fuso.
#
# É dado, não fala: a instrução adapta a resposta e só orienta o que o perfil pode fazer. O modelo
# nunca confia nisso para autorizar — é só para a redação; o backend real (endpoints de domínio) é
# que aplica Pundit.
module Autonomia::Guide::Cabecalho
  def self.call(account:, role:, route_context:, route_params:)
    "[CONTEXTO INTERNO (não é fala do usuário). Perfil do usuário: #{role}. " \
      "Tela atual: #{route_context.presence || 'não informada'}.#{registro_aberto(route_params)}#{fuso(account)} " \
      'Adapte a resposta a este perfil e oriente apenas o que ele pode fazer; se a ação for de administrador e o ' \
      'perfil não for administrator, explique que é feito pelo administrador da conta.]'
  end

  # #859 — o registro que a pessoa tem aberto na tela (ex.: id=42 na tela da automação).
  # Só números, filtrados no controller; é contexto, não autorização.
  def self.registro_aberto(route_params)
    return '' if route_params.blank?

    " Registro aberto na tela: #{route_params.map { |chave, valor| "#{chave}=#{valor}" }.join(', ')}."
  end

  # #954 — o fuso da conta, que a tela grava sozinha a partir do navegador. Com ele o Guia marca
  # "às 9h" no horário de quem pediu, e não em UTC nem em São Paulo para quem está em Cuiabá.
  def self.fuso(account)
    fuso = account.custom_attributes&.dig('timezone').presence || account.reporting_timezone.presence
    fuso ? " Fuso da conta: #{fuso}." : ''
  end
end
