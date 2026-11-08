# frozen_string_literal: true

# Nicho dos agentes da conta (#1429): de qual base partem as instruções dos agentes novos. Lugar ÚNICO de leitura.
#
# Mesmo desenho da marca da Cotação (Autonomia::Insurance::Config): fica no jsonb interno `accounts.internal_attributes`,
# escolhido só pelo super admin, sem coluna nova em tabela do Chatwoot. Três chaves:
#   - NICHO_KEY:  'seguros' | 'geral';
#   - PERFIL_KEY: 'corretora' | 'seguradora' | 'insurtech' | 'saude_beneficios', que só vale com seguros;
#   - CANAL_KEY:  'direto' | 'corretores' | 'parceiros', como a insurtech vende; só vale com o perfil insurtech.
#
# Sem escolha da conta, vale o padrão da instalação: InstallationConfig AUTONOMIA_NICHO_PADRAO, e na falta dele a ENV
# de mesmo nome ("seguros:insurtech:direto", "seguros:corretora", "seguros" ou "geral"; sem nada, "geral"). Valor
# inválido, na conta ou na instalação, não quebra a leitura: cai no padrão (ou em geral) e fica no log. A insurtech
# sem canal (ou com canal inválido) vale "direto", na conta e no padrão: é como ela fala até o canal ser escolhido, e
# o formulário sempre manda um canal marcado. Canal inválido não invalida nicho e perfil.
#
# Trocar o nicho não muda agente que já existe: ele só muda pelo botão "Atualizar com a nova base". Lido por
# Autonomia::Segmentos::Pacotes (#1550), que escolhe as palavras da conta pelo nicho e pelo perfil; o canal fica só
# guardado nesta fase.
module Autonomia::Agents::Nicho
  NICHO_KEY = 'autonomia_agents_nicho'
  PERFIL_KEY = 'autonomia_agents_perfil'
  CANAL_KEY = 'autonomia_agents_canal'
  PADRAO_KEY = 'AUTONOMIA_NICHO_PADRAO'
  SEGUROS = 'seguros'
  GERAL = 'geral'
  NICHOS = [SEGUROS, GERAL].freeze
  # Valor do formulário para "seguir o padrão da instalação": não é nicho, só apaga a escolha da conta.
  PADRAO = 'padrao'
  INSURTECH = 'insurtech'
  PERFIS = %w[corretora seguradora insurtech saude_beneficios].freeze
  PERFIL_PADRAO = 'corretora'
  CANAIS = %w[direto corretores parceiros].freeze
  CANAL_PADRAO = 'direto'
  LOG_TAG = '[Autonomia::Agents::Nicho]'

  # padrao? diz se o valor veio da instalação (a conta não escolheu, ou escolheu algo inválido).
  # canal: sempre preenchido na insurtech ("direto" quando não informado); nil nos outros perfis.
  Escolha = Data.define(:nicho, :perfil, :canal, :padrao) do
    def initialize(nicho:, perfil:, padrao:, canal: nil) = super

    def padrao?
      padrao
    end
  end

  def self.for(account)
    salvo = account.internal_attributes.to_h
    return padrao_da_instalacao if salvo[NICHO_KEY].blank?

    escolha = escolher(salvo[NICHO_KEY], salvo[PERFIL_KEY], salvo[CANAL_KEY], padrao: false)
    return escolha if escolha

    Rails.logger.warn("#{LOG_TAG} account=#{account.id} valor gravado inválido " \
                      "(nicho=#{salvo[NICHO_KEY].inspect}, perfil=#{salvo[PERFIL_KEY].inspect}); usando o padrão da instalação")
    padrao_da_instalacao
  end

  def self.padrao_da_instalacao
    bruto = GlobalConfig.get_value(PADRAO_KEY).presence || ENV.fetch(PADRAO_KEY, nil).presence
    return Escolha.new(nicho: GERAL, perfil: nil, padrao: true) if bruto.blank?

    escolha = escolher(*partes_do_padrao(bruto), padrao: true)
    return escolha if escolha

    Rails.logger.warn("#{LOG_TAG} #{PADRAO_KEY} inválido (#{bruto.inspect}); usando #{GERAL}")
    Escolha.new(nicho: GERAL, perfil: nil, padrao: true)
  end

  # "seguros:insurtech:direto" → [nicho, perfil, canal]; seguros sem perfil vira corretora. O canal que faltar é
  # completado em canal_do, igual para a conta e para o padrão.
  def self.partes_do_padrao(bruto)
    nicho, perfil, canal = bruto.to_s.strip.split(':', 3)
    [nicho, perfil.presence || (PERFIL_PADRAO if nicho == SEGUROS), canal]
  end
  private_class_method :partes_do_padrao

  # Atribui a escolha do super admin em internal_attributes, sem salvar e sem tocar nas outras chaves. Valor fora da
  # lista não muda nada. PADRAO apaga nicho, perfil e canal: a conta volta a seguir o padrão da instalação.
  def self.atribuir(account, nicho:, perfil:, canal: nil)
    return voltar_ao_padrao(account) if nicho.to_s == PADRAO

    escolha = escolher(nicho, perfil, canal, padrao: false)
    return if escolha.nil?

    escolhidas = { NICHO_KEY => escolha.nicho, PERFIL_KEY => escolha.perfil, CANAL_KEY => escolha.canal }.compact
    account.internal_attributes = account.internal_attributes.to_h.except(PERFIL_KEY, CANAL_KEY).merge(escolhidas)
  end

  def self.voltar_ao_padrao(account)
    account.internal_attributes = account.internal_attributes.to_h.except(NICHO_KEY, PERFIL_KEY, CANAL_KEY)
  end
  private_class_method :voltar_ao_padrao

  def self.escolher(nicho, perfil, canal, padrao:)
    nicho = nicho.to_s
    return Escolha.new(nicho: GERAL, perfil: nil, padrao: padrao) if nicho == GERAL
    return unless nicho == SEGUROS && PERFIS.include?(perfil.to_s)

    Escolha.new(nicho: SEGUROS, perfil: perfil.to_s, canal: canal_do(perfil.to_s, canal), padrao: padrao)
  end
  private_class_method :escolher

  # Canal só existe na insurtech; sem canal ou fora da lista, vale o padrão (direto).
  def self.canal_do(perfil, canal)
    return unless perfil == INSURTECH

    CANAIS.include?(canal.to_s) ? canal.to_s : CANAL_PADRAO
  end
  private_class_method :canal_do
end
