# frozen_string_literal: true

# Nicho dos agentes da conta (#1429): de qual base partem as instruções dos agentes novos. Lugar ÚNICO de leitura.
#
# Mesmo desenho da marca da Cotação (Autonomia::Insurance::Config): fica no jsonb interno `accounts.internal_attributes`,
# escolhido só pelo super admin, sem coluna nova em tabela do Chatwoot. Duas chaves:
#   - NICHO_KEY:  'seguros' | 'geral';
#   - PERFIL_KEY: 'corretora' | 'seguradora' | 'insurtech', que só vale com seguros.
#
# Sem escolha da conta, vale o padrão da instalação: InstallationConfig AUTONOMIA_NICHO_PADRAO, e na falta dele a ENV
# de mesmo nome ("seguros:corretora", "seguros" ou "geral"; sem nada, "geral"). Valor inválido, na conta ou na
# instalação, não quebra a leitura: cai no padrão (ou em geral) e fica no log.
#
# Trocar o nicho não muda agente que já existe: ele só muda pelo botão "Atualizar com a nova base". Nesta fase nada lê
# o nicho para mudar instrução (tema 8, F2).
module Autonomia::Agents::Nicho
  NICHO_KEY = 'autonomia_agents_nicho'
  PERFIL_KEY = 'autonomia_agents_perfil'
  PADRAO_KEY = 'AUTONOMIA_NICHO_PADRAO'
  SEGUROS = 'seguros'
  GERAL = 'geral'
  NICHOS = [SEGUROS, GERAL].freeze
  PERFIS = %w[corretora seguradora insurtech].freeze
  PERFIL_PADRAO = 'corretora'
  LOG_TAG = '[Autonomia::Agents::Nicho]'

  # padrao? diz se o valor veio da instalação (a conta não escolheu, ou escolheu algo inválido).
  Escolha = Data.define(:nicho, :perfil, :padrao) do
    def padrao?
      padrao
    end
  end

  def self.for(account)
    salvo = account.internal_attributes.to_h
    return padrao_da_instalacao if salvo[NICHO_KEY].blank?

    escolha = escolher(salvo[NICHO_KEY], salvo[PERFIL_KEY], padrao: false)
    return escolha if escolha

    Rails.logger.warn("#{LOG_TAG} account=#{account.id} valor gravado inválido " \
                      "(nicho=#{salvo[NICHO_KEY].inspect}, perfil=#{salvo[PERFIL_KEY].inspect}); usando o padrão da instalação")
    padrao_da_instalacao
  end

  def self.padrao_da_instalacao
    bruto = GlobalConfig.get_value(PADRAO_KEY).presence || ENV.fetch(PADRAO_KEY, nil).presence
    return Escolha.new(nicho: GERAL, perfil: nil, padrao: true) if bruto.blank?

    nicho, perfil = bruto.to_s.strip.split(':', 2)
    escolha = escolher(nicho, perfil.presence || (PERFIL_PADRAO if nicho == SEGUROS), padrao: true)
    return escolha if escolha

    Rails.logger.warn("#{LOG_TAG} #{PADRAO_KEY} inválido (#{bruto.inspect}); usando #{GERAL}")
    Escolha.new(nicho: GERAL, perfil: nil, padrao: true)
  end

  # Atribui a escolha do super admin em internal_attributes, sem salvar e sem tocar nas outras chaves. Valor fora da
  # lista não muda nada. Se a conta ainda não escolheu e recebe o próprio padrão da instalação (o formulário sempre
  # manda o cartão marcado), nada é gravado: a conta continua seguindo o padrão.
  def self.atribuir(account, nicho:, perfil:)
    escolha = escolher(nicho, perfil, padrao: false)
    return if escolha.nil?
    return if account.internal_attributes.to_h[NICHO_KEY].blank? && mesma?(escolha, padrao_da_instalacao)

    account.internal_attributes = account.internal_attributes.to_h.except(PERFIL_KEY)
                                         .merge({ NICHO_KEY => escolha.nicho, PERFIL_KEY => escolha.perfil }.compact)
  end

  def self.escolher(nicho, perfil, padrao:)
    nicho = nicho.to_s
    return Escolha.new(nicho: GERAL, perfil: nil, padrao: padrao) if nicho == GERAL
    return unless nicho == SEGUROS && PERFIS.include?(perfil.to_s)

    Escolha.new(nicho: SEGUROS, perfil: perfil.to_s, padrao: padrao)
  end
  private_class_method :escolher

  def self.mesma?(uma, outra)
    uma.nicho == outra.nicho && uma.perfil == outra.perfil
  end
  private_class_method :mesma?
end
