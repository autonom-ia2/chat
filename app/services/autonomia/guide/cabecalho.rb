# O CONTEXTO INTERNO que abre a pergunta do Guia: perfil, tela, registro aberto e fuso.
#
# É dado, não fala: a instrução adapta a resposta e só orienta o que o perfil pode fazer. O modelo
# nunca confia nisso para autorizar — é só para a redação; o backend real (endpoints de domínio) é
# que aplica Pundit.
module Autonomia::Guide::Cabecalho
  def self.call(account:, role:, route_context:, route_params:)
    "[CONTEXTO INTERNO (não é fala do usuário). Perfil do usuário: #{role}. " \
      "Tela atual: #{route_context.presence || 'não informada'}." \
      "#{automacao_do_motor(account, route_context, route_params) || registro_aberto(route_params)}#{fuso(account)}" \
      "#{motor_das_automacoes(account)} " \
      'Adapte a resposta a este perfil e oriente apenas o que ele pode fazer; se a ação for de administrador e o ' \
      "perfil não for administrator, explique que é feito pelo administrador da conta#{quem_mais_monta_automacao(account)}.]"
  end

  # #2414 F1.3: com a flag, regras automáticas também para quem tem a permissão delas (PorteiroDaAutomacao).
  def self.quem_mais_monta_automacao(account)
    Autonomia::Automacao.fundacao?(account) ? ' (regras automáticas: também quem tem a permissão delas na função)' : ''
  end

  # #859 — o registro que a pessoa tem aberto na tela (ex.: id=42 na tela da automação).
  # Só números, filtrados no controller; é contexto, não autorização.
  def self.registro_aberto(route_params)
    return '' if route_params.blank?

    " Registro aberto na tela: #{route_params.map { |chave, valor| "#{chave}=#{valor}" }.join(', ')}."
  end

  # #2889 — com a porta da Automação (e o editor, que a API pede), o Guia monta automação no motor novo
  # (autonomia/automacoes), e não em automation_rules. Sem as duas flags, a linha não existe e tudo segue como antes.
  FLAGS_DO_MOTOR_NOVO = %w[automacao_porta automacao_editor].freeze
  TELA_DO_MOTOR_NOVO = 'automacoes_guia_editar'.freeze

  def self.motor_novo?(account)
    account.present? && FLAGS_DO_MOTOR_NOVO.all? { |flag| account.feature_enabled?(flag) }
  end

  def self.motor_das_automacoes(account)
    motor_novo?(account) ? ' Motor das automações desta conta: novo (autonomia/automacoes).' : ''
  end

  # #2889 — na tela de uma automação do motor novo, o id dela e o da versão atual: o ajuste (PATCH) leva a versão
  # como base_versao_id. Lida aqui, a cada pergunta, para valer a versão que o último ajuste gravou. Só da conta;
  # é contexto, não autorização.
  def self.automacao_do_motor(account, route_context, route_params)
    return unless route_context.to_s == TELA_DO_MOTOR_NOVO && motor_novo?(account)

    id = route_params.to_h.with_indifferent_access[:id]
    automacao = id && ::Autonomia::Automacao::Definicao.find_by(account_id: account.id, id: id)
    return unless automacao

    " Registro aberto na tela: automação id=#{automacao.id}, versão atual id=#{automacao.versao_ativa_id}" \
      "#{', ligada' if automacao.ativa}."
  end

  # #954 — o fuso da conta, que a tela grava sozinha a partir do navegador. Com ele o Guia marca
  # "às 9h" no horário de quem pediu, e não em UTC nem em São Paulo para quem está em Cuiabá.
  def self.fuso(account)
    fuso = account.custom_attributes&.dig('timezone').presence || account.reporting_timezone.presence
    fuso ? " Fuso da conta: #{fuso}." : ''
  end
end
