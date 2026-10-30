# #1426 (tema 4b) — o AUTOTESTE do material: no máximo 10 perguntas, 8 do material e 2 de fora dele. O agente responde
# como no Testar, SEM ferramenta nenhuma (o mesmo modo `prova` do #1428: nada é executado nem chega a cliente), e um
# juiz dá o veredito (JuizDoAutoteste). Roda quando a pessoa pede ("Testar de novo": um a cada 2 min, 10 por dia) ou
# quando a base muda (BaseMudouJob: no máximo uma rodada automática a cada 30 min por agente, e só se a base mudou
# desde a última). Os limites por dia: LimiteDoAutoteste.
#
# CUSTO: teto de US$ 2 por rodada, com contagem real (MedidorDeCusto). Antes de cada chamada a rodada confere se cabe;
# se não couber, PARA ANTES e fica "parado" (motivo `teto`). O teto pode passar em até uma chamada (a estimativa da
# próxima é piso, não garantia). O custo sai da chave de IA da conta (app `crm_kanban_ai`) ou, sem ela, da chave da
# plataforma (CredentialResolver), como o resto dos Agentes, e aparece na Gestão IA com os rótulos `agente_autoteste_*`.
#
# Guarda em config['autoteste'] (ConfigDoMaterial, escrita atômica):
#   rodada, estado (rodando | pronto | parado), motivo (teto | indisponivel), quando (pedido | base_mudou), desde,
#   feitas, total, gasto_usd, hash_da_base, ultima_automatica,
#   rodada_dos_itens (a rodada que produziu os itens: o id dos cartões não muda quando outra rodada começa),
#   itens: o ÚLTIMO resultado completo — [{ pergunta, origem (material | fora), esperado, fonte, resposta, equipe,
#          trechos (t4d: até 3 trechos usados, { fonte, paginas, texto }), veredito (certo | errado | recusou | inventou),
#          confirmada }]
# Os itens só são trocados quando a rodada termina: a rodada que para no meio não apaga o resultado anterior (nem os
# problemas que ele mostra).
class Autonomia::Agents::Material::Autoteste
  CHAVE = 'autoteste'.freeze
  LIMITE = Autonomia::Agents::Material::LimiteDoAutoteste
  RESPOSTA_FEATURE = 'agente_autoteste_resposta'.freeze
  # Rodando há mais que isto, a rodada morreu (worker caiu): a tela mostra "não consegui terminar" e libera de novo.
  VALIDADE_DA_RODADA = 15.minutes
  INTERVALO_AUTOMATICO = 30.minutes
  # Base mudou com uma rodada rodando: confere de novo depois disto (a rodada leva 1 a 3 min).
  ESPERA_DA_RODADA_VIVA = 5.minutes
  # "De onde {agente} tirou" (t4d): quantos trechos usados a rodada guarda por pergunta e até onde vai o texto de cada.
  TRECHOS_POR_RESPOSTA = 3
  TRECHO_MAX_CHARS = 240
  FALHAS_DA_IA = [Crm::Ai::ResponsesClient::Error, JSON::ParserError, *Crm::Ai::ResponsesClient::NETWORK_ERRORS,
                  OpenSSL::SSL::SSLError, Errno::EHOSTUNREACH, Errno::ENETUNREACH].freeze

  class << self
    # Começa uma rodada (estado `rodando`) e a enfileira. Com uma rodada viva, devolve a dela, sem outra. nil fora do
    # material da Fase 2 ou sem material aprovado. Passado o limite: o pedido da pessoa levanta LimiteDoAutoteste::Excedido;
    # a rodada automática só não abre (nil).
    def pedir!(agent, quando:)
      return unless Autonomia::Agents::Material.conferir?(agent) && agent.sources.knowledge_sources.servable.exists?

      rodada, bloqueio, estado = abrir_rodada(agent, quando)
      raise LIMITE::Excedido, bloqueio if bloqueio && quando == 'pedido'
      return if bloqueio

      Autonomia::Agents::Material::AutotesteJob.perform_later(agent.id, rodada) if rodada
      estado
    end

    # A rodada automática: só com a base mudada desde a última rodada, sem rodada viva e 30 min depois da última
    # automática. Devolve QUANDO ela pode rodar (agora, ou mais tarde: o fim dos 30 min, ou daqui a pouco se há rodada
    # viva), ou nil quando a base é a mesma da última rodada (nada novo a testar).
    def quando_automatica(agent)
      atual = agent.chave_do_material(CHAVE).to_h
      return if atual['hash_da_base'] == Autonomia::Agents::Material.hash_da_base(agent)

      ultima = Time.zone.parse(atual['ultima_automatica'].to_s)
      livre = [ultima && (ultima + INTERVALO_AUTOMATICO), Time.current].compact.max
      viva?(atual) ? [livre, ESPERA_DA_RODADA_VIVA.from_now].max : livre
    end

    def viva?(estado)
      estado.is_a?(Hash) && estado['estado'] == 'rodando' && !vencida?(estado)
    end

    def vencida?(estado)
      desde = Time.zone.parse(estado['desde'].to_s)
      desde.nil? || desde.before?(VALIDADE_DA_RODADA.ago)
    end

    private

    # Sob a trava da linha: confere o limite, conta e abre. -> [rodada aberta ou nil, motivo do bloqueio ou nil, estado]
    def abrir_rodada(agent, quando)
      plataforma = LIMITE.da_plataforma?(agent)
      rodada = bloqueio = nil
      estado = agent.alterar_chave_do_material!(CHAVE) do |atual|
        next if viva?(atual)

        bloqueio = LIMITE.bloqueio(atual, quando, plataforma)
        next if bloqueio

        rodada = SecureRandom.hex(8)
        LIMITE.contar(nova_rodada(atual, rodada, quando, agent), atual, quando, plataforma)
      end
      [rodada, bloqueio, estado]
    end

    def nova_rodada(atual, rodada, quando, agent)
      base = atual.is_a?(Hash) ? atual.slice('itens', 'rodada_dos_itens', 'ultima_automatica') : {}
      base = base.merge('ultima_automatica' => Time.current.iso8601) if quando == 'base_mudou'
      base.merge('rodada' => rodada, 'estado' => 'rodando', 'motivo' => nil, 'quando' => quando, 'desde' => Time.current.iso8601,
                 'feitas' => 0, 'total' => 0, 'gasto_usd' => 0.0, 'hash_da_base' => Autonomia::Agents::Material.hash_da_base(agent))
    end
  end

  def initialize(agent, rodada, medidor: Autonomia::Agents::Material::MedidorDeCusto.new)
    @agent = agent
    @rodada = rodada
    @medidor = medidor
  end

  def rodar!
    comecar!
    return unless vigente?

    itens = perguntas
    respondidos = itens && responder_todas(itens)
    julgar_e_gravar!(respondidos) if respondidos
  rescue *FALHAS_DA_IA => e
    Rails.logger.warn("[autonomia][autoteste] falhou agent=#{@agent.id} #{e.class}")
    parar!('indisponivel')
  end

  private

  # As perguntas da rodada, com a origem marcada. nil quando a rodada parou (teto ou IA indisponível).
  def perguntas
    geradas = chamar(:perguntas) { Autonomia::Agents::Material::PerguntasDoAutoteste.new(@agent).gerar }
    return if geradas == :parou

    if geradas.nil?
      parar!('indisponivel')
      return
    end

    geradas[:material].map { |item| item.merge('origem' => 'material') } +
      geradas[:fora].map { |item| item.merge('origem' => 'fora') }
  end

  def responder_todas(itens)
    progresso!('total' => itens.size)
    itens.each_with_index.map do |item, indice|
      return nil unless vigente?

      resposta = chamar(:resposta) { responder(item['pergunta']) }
      return nil if resposta == :parou

      if resposta.nil?
        parar!('indisponivel')
        return nil
      end

      progresso!('feitas' => indice + 1)
      item.merge(resposta)
    end
  end

  def julgar_e_gravar!(itens)
    vereditos = chamar(:juiz) { Autonomia::Agents::Material::JuizDoAutoteste.new(account: @agent.account).julgar(itens) }
    return if vereditos == :parou
    return parar!('indisponivel') if vereditos.nil?

    julgados = itens.zip(vereditos).map { |item, veredito| item.merge('veredito' => veredito) }
    finalizar!('estado' => 'pronto', 'rodada_dos_itens' => @rodada, 'itens' => julgados)
  end

  # Cabe no teto? Mede e chama; não cabe, para antes (`:parou`).
  def chamar(tipo, &)
    unless @medidor.cabe?(tipo)
      parar!('teto')
      return :parou
    end

    @medidor.medir(tipo, &)
  end

  # A resposta do agente pelo caminho do Testar, sem ferramenta. nil quando a IA falhou.
  def responder(pergunta)
    resultado = Autonomia::Agents::Answerer.new(agent: @agent, query: pergunta, feature: RESPOSTA_FEATURE, prova: true,
                                                trust_instruction: Autonomia::Agents::Playground.como_no_atendimento?(@agent)).answer
    texto = resultado.reply.to_s.strip.presence
    equipe = resultado.handoff[:should] == true
    return if resultado.error.present? || (texto.nil? && !equipe)

    { 'resposta' => texto, 'equipe' => equipe, 'trechos' => trechos_usados(resultado.used_knowledge) }
  end

  # Só trechos do material deste agente (a imagem da mensagem e o que não é dele ficam de fora), na ordem do Answerer.
  def trechos_usados(usados)
    ids = Array(usados).filter_map { |usado| usado[:id] }
    por_id = @agent.knowledge_entries.where(id: ids).index_by(&:id)
    ids.filter_map { |id| por_id[id] }.first(TRECHOS_POR_RESPOSTA).map do |trecho|
      { 'fonte' => trecho.source_id, 'paginas' => trecho.metadata.to_h['paginas'],
        'texto' => trecho.content.to_s.squish.truncate(TRECHO_MAX_CHARS) }.compact
    end
  end

  # O prazo da rodada conta do começo do job, não do pedido: com a fila atrasada, a rodada não nasce vencida. Só a
  # rodada vigente (outra pedida no meio vence).
  def comecar!
    alterar! { |atual| atual.merge('desde' => Time.current.iso8601) }
  end

  def vigente?
    estado = @agent.reload.chave_do_material(CHAVE).to_h
    estado['rodada'] == @rodada && estado['estado'] == 'rodando' && !self.class.vencida?(estado)
  end

  def progresso!(mudanca)
    alterar! { |atual| atual.merge(mudanca).merge('gasto_usd' => @medidor.gasto.round(4)) }
  end

  def parar!(motivo)
    finalizar!('estado' => 'parado', 'motivo' => motivo)
  end

  def finalizar!(mudanca)
    alterar! { |atual| atual.merge(mudanca).merge('gasto_usd' => @medidor.gasto.round(4)) }
    Rails.logger.info("[autonomia][autoteste] agent=#{@agent.id} rodada=#{@rodada} #{mudanca['estado']} " \
                      "motivo=#{mudanca['motivo']} gasto_usd=#{@medidor.gasto.round(4)}")
    true
  end

  # Só escreve se a rodada ainda é esta e está rodando (outra rodada pedida no meio vence).
  def alterar!
    @agent.alterar_chave_do_material!(CHAVE) do |atual|
      yield(atual) if atual.is_a?(Hash) && atual['rodada'] == @rodada && atual['estado'] == 'rodando'
    end
  end
end
