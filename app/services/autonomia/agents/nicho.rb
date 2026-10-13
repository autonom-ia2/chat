# frozen_string_literal: true

# Nicho dos agentes da conta (#1429): de qual base as instruções dos agentes novos partem. Fica no jsonb interno
# `accounts.internal_attributes` (o mesmo lugar da marca da Cotação), escolhido só pelo super admin. Sem escolha, vale
# o padrão da instalação (ENV AUTONOMIA_NICHO_PADRAO, "seguros:corretora" ou "geral"; sem ENV, "geral").
# Trocar o nicho não muda agente que já existe: ele só muda pelo botão "Atualizar com a nova base".
module Autonomia::Agents::Nicho
  INTERNAL_ATTR_KEY = 'autonomia_agents_nicho'
  ENV_PADRAO = 'AUTONOMIA_NICHO_PADRAO'
  SEGUROS = 'seguros'
  GERAL = 'geral'
  NICHOS = [SEGUROS, GERAL].freeze
  PERFIS = %w[corretora seguradora insurtech].freeze
  PERFIL_PADRAO = 'corretora'

  # { 'nicho' => 'seguros', 'perfil' => 'corretora' } ou { 'nicho' => 'geral' }; valor desconhecido devolve nil.
  def self.normalizar(nicho, perfil = nil)
    nicho = nicho.to_s
    return nil unless NICHOS.include?(nicho)
    return { 'nicho' => GERAL } if nicho == GERAL

    { 'nicho' => SEGUROS, 'perfil' => PERFIS.include?(perfil.to_s) ? perfil.to_s : PERFIL_PADRAO }
  end

  def self.padrao_da_instalacao
    nicho, perfil = ENV.fetch(ENV_PADRAO, GERAL).to_s.split(':', 2)
    normalizar(nicho, perfil) || { 'nicho' => GERAL }
  end

  def self.da_conta(account)
    salvo = account.internal_attributes.to_h[INTERNAL_ATTR_KEY]
    return nil unless salvo.is_a?(Hash)

    normalizar(salvo['nicho'], salvo['perfil'])
  end

  def self.efetivo(account)
    da_conta(account) || padrao_da_instalacao
  end
end
