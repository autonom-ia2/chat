# F3 do tema 8 (#1429): o antes e depois de "Atualizar com a nova base". As perguntas do tipo da base NOVA
# (Bloco.perguntas, no idioma de quem pediu), respondidas pelo agente como ele está hoje e com a base nova.
#
# É o motor do Testar (Answerer, com a etiqueta de custo do Testar), sem ferramenta nenhuma (modo `prova`, como a prova do
# ajuste e o autoteste): nada é executado nem chega a cliente. A base nova vai numa cópia do agente só na memória, só
# leitura: nada é gravado, nem no agente nem no histórico. Roda num job (Crm::Ai::InteractiveJob); a tela busca o
# resultado. Se a IA falha em qualquer resposta (ou qualquer outra coisa falha), a comparação inteira falha e o agente
# fica livre para tentar de novo.
class Autonomia::Agents::BaseDeSeguros::Comparacao
  class SemBaseNova < StandardError; end
  class Falhou < StandardError; end

  # `account_user`: quem pediu. Ao fim, fica guardado que essa pessoa viu esta versão (Comparada): só ela pode atualizar.
  def initialize(agent, idioma:, account_user:)
    @agent = agent
    @idioma = idioma
    @account_user = account_user
  end

  # -> { versao, perguntas: [{ pergunta, hoje, hoje_equipe, nova, nova_equipe }] }. `versao`: a da base nova comparada, que
  # a tela manda de volta no "atualizar" (a guarda contra gravar uma base que a pessoa não viu).
  def rodar
    marca = Autonomia::Agents::BaseDeSeguros.new(@agent).marca_nova
    raise SemBaseNova if marca.nil?

    perguntas = Autonomia::Segmentos::Bloco.perguntas(marca['segmento'], @idioma)
    raise SemBaseNova if perguntas.blank?

    com_a_nova = agente_com_a_base(marca)
    resultado = { versao: marca['versao'], perguntas: perguntas.map { |pergunta| comparar(pergunta, com_a_nova) } }
    Autonomia::Agents::BaseDeSeguros::Comparada.guardar!(@agent, @account_user, @idioma, resultado)
    resultado
  rescue StandardError
    Autonomia::Agents::BaseDeSeguros::Limite.liberar!(@agent)
    raise
  end

  private

  def comparar(pergunta, com_a_nova)
    hoje = responder(@agent, pergunta)
    nova = responder(com_a_nova, pergunta)
    { pergunta: pergunta, hoje: hoje[:texto], hoje_equipe: hoje[:equipe], nova: nova[:texto], nova_equipe: nova[:equipe] }
  end

  # O MESMO agente comparado, sem reler o banco: uma cópia dos atributos como iriam ao banco (o enum alterado em memória
  # fica como está, e o jsonb não divide objeto com o agente), com a base nova só na memória. "Hoje", "nova" e a marca de
  # quem viu saem do mesmo retrato. É um registro salvo (com o id), para o caminho do Testar achar o material dele.
  # readonly!: se algo no caminho tentar salvá-lo, falha.
  def agente_com_a_base(marca)
    copia = Autonomia::Agents::Agent.instantiate(@agent.attributes_for_database)
    copia.config = copia.config.to_h.merge('base' => marca)
    copia.readonly!
    copia
  end

  # A resposta pelo caminho do Testar, sem ferramenta. `equipe`: o agente passaria a conversa para a equipe.
  def responder(agent, pergunta)
    resultado = Autonomia::Agents::Answerer.new(agent: agent, query: pergunta, feature: Autonomia::Agents::Playground::USAGE_FEATURE,
                                                prova: true).answer
    texto = resultado.reply.to_s.strip.presence
    equipe = resultado.handoff[:should] == true
    raise Falhou if resultado.error.present? || (texto.nil? && !equipe)

    { texto: texto, equipe: equipe }
  rescue *Autonomia::Agents::ProvaDoAjuste::FALHAS_DA_IA => e
    Rails.logger.warn("[autonomia][base_de_seguros] comparação falhou agente=#{@agent.id} #{e.class}")
    raise Falhou
  end
end
