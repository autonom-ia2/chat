# F3 do tema 8 (#1429): a linha "Base de seguros" da página do agente. Diz com que base ele trabalha (o tipo e a data do
# texto), se existe uma nova, e troca a base pelo botão "Atualizar com a nova base".
#
# SITUAÇÕES (com a marca gravada no agente, `config['base']`, e a marca que um agente nascendo agora receberia):
#   sem_base    o agente não tem texto de base (sem marca, ou texto nil) e a conta de seguros tem um;
#   antiga      mesmo segmento, outra versão do texto;
#   conta_mudou o segmento gravado não é mais o da conta (inclusive conta que deixou de ser de seguros: aí não há base
#               nova, e o botão não aparece);
#   em_dia      o resto.
# A linha não aparece (nil) na conta geral com agente sem base, sem a Fase 2, na Lia (instrução mantida), no Guia
# (system_key) e quando a leitura do tipo da conta falha (SegmentoDoAgente.marca devolve nil).
#
# O texto da base é dado nosso: nunca sai daqui, só o segmento, a versão nova (para a guarda do "atualizar") e a data.
class Autonomia::Agents::BaseDeSeguros
  TROCAVEIS = %w[sem_base antiga conta_mudou].freeze

  # Não há base nova para gravar (em dia, ou a conta não tem texto).
  class SemBaseNova < StandardError; end
  # A base nova não é mais a que a pessoa viu (a versão mudou entre a leitura e o clique).
  class VersaoMudou < StandardError; end

  def self.elegivel?(agent)
    Autonomia::Agents::Fase2.ligada?(agent.account) && !agent.instrucao_mantida? && agent.config.to_h['system_key'].blank?
  end

  def initialize(agent)
    @agent = agent
  end

  # O que a linha mostra, ou nil quando ela não aparece.
  def to_h
    situacao = situacao_atual
    return if situacao.nil?

    { situacao: situacao, atual: descrever(atual), nova: nova_publica, pode_atualizar: pode_atualizar?, desfazer: desfazer }
  end

  # A marca a gravar no "Atualizar com a nova base"; nil quando não há base nova.
  def marca_nova
    marca = marca_da_conta
    marca if marca && marca['texto'].present? && TROCAVEIS.include?(situacao_atual)
  end

  # Grava a base nova. `versao`: a da base nova que a pessoa viu (a guarda contra trocar por outra).
  def atualizar!(created_by:, versao: nil)
    marca = marca_nova
    raise SemBaseNova if marca.nil? || !@agent.troca_da_base_disponivel?
    raise VersaoMudou if versao.present? && versao != marca['versao']

    @agent.trocar_base!(marca, created_by: created_by)
  end

  private

  def situacao_atual
    return unless self.class.elegivel?(@agent) && marca_da_conta

    tem_nova = marca_da_conta['texto'].present?
    return (tem_nova ? 'sem_base' : nil) if atual.nil?

    situacao_com_base(tem_nova)
  end

  def situacao_com_base(tem_nova)
    return 'conta_mudou' if atual['segmento'] != marca_da_conta['segmento']
    return 'antiga' if tem_nova && atual['versao'] != marca_da_conta['versao']

    'em_dia'
  end

  # A marca com que um agente nasceria agora nesta conta (nil sem a Fase 2 ou com a leitura do tipo falhando).
  def marca_da_conta
    return @marca_da_conta if defined?(@marca_da_conta)

    @marca_da_conta = Autonomia::Agents::PromptParts::SegmentoDoAgente.marca(@agent.account)
  end

  # A marca gravada, quando tem texto.
  def atual
    base = @agent.config.to_h['base']
    base if base.is_a?(Hash) && base['texto'].present?
  end

  def nova_publica
    marca = marca_nova
    marca && descrever(marca).merge(versao: marca['versao'])
  end

  def pode_atualizar?
    marca_nova.present? && @agent.troca_da_base_disponivel?
  end

  def desfazer
    aplicada = @agent.base_desfazivel
    return if aplicada.nil?

    anterior = @agent.base_antes_da_troca(aplicada)
    { anterior: anterior.is_a?(Hash) && anterior['texto'].present? ? descrever(anterior) : nil }
  end

  def descrever(base)
    return if base.nil?

    { segmento: base['segmento'], data: Autonomia::Segmentos::Bloco.data_da_versao(base['segmento'], base['versao']) }
  end
end
