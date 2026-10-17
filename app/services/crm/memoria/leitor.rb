# TODA LEITURA DA MEMÓRIA PELAS IAs PASSA AQUI (#1601). Formato combinado com o Agentes IA (16/10/2026), que monta os
# blocos no Responder e no especialista:
#
#   Crm::Memoria::Leitor.para(finalidade:, account:, conversation:, agent: nil, teto_a: 1800, teto_b: 900) -> Leitura
#
# Leitura (imutável):
#   antes            bloco A, estável enquanto durar a posse: a identidade do cliente (fatos do contato) e os pedidos
#                    encerrados (D6, 360 d)
#   agora_do_sistema só o que o CÓDIGO gera (origem :sistema): o canal, o que falta (chaves obrigatórias vazias do
#                    pedido em foco) e o dono previsto da próxima passagem
#   agora_fatos      os fatos do pedido em foco (obrigatórias primeiro, A13), as decisões, os da conversa e, depois, os
#                    dos outros pedidos abertos do mesmo cliente (D5: os fatos do cliente valem em todos os funis)
#   ids              os ids dos fatos ENVIADOS (rastreabilidade: o que a IA leu)
#   card_em_foco_id  o card em foco da conversa, nil sem card
#
# Linha: id, chave, rotulo, valor, origem (:cliente_informou | :confirmado | :equipe | :ferramenta | :sistema), em (Time
# absoluto), message_id, card_id, status (:vigente | :divergente | :vencido). Sugestão (quarentena) nunca entra; nem
# fato cuja única prova é a nossa IA.
#
# Isolamento: sempre a conta e o CONTATO da conversa (D5 tirou a trava de funil; ficam contato e conta). A flag
# desligada ou a caixa fora da memória devolvem a leitura vazia. Teto em caracteres, pela linha em JSON: nunca corta uma
# linha no meio. O valor sai numa linha, sem caracteres invisíveis (TextoSemDisfarce).
class Crm::Memoria::Leitor
  FINALIDADES = %i[responder especialista avaliacao assunto bilhete].freeze
  MAXIMO_POR_GRUPO = 100
  ORIGEM_DA_FONTE = { 'cliente' => :cliente_informou, 'equipe' => :equipe, 'ferramenta_resultado' => :ferramenta,
                      'sistema' => :sistema, 'pessoa_corrigiu' => :confirmado }.freeze

  Linha = Data.define(:id, :chave, :rotulo, :valor, :origem, :em, :message_id, :card_id, :status)

  Leitura = Data.define(:antes, :agora_do_sistema, :agora_fatos, :ids, :card_em_foco_id) do
    def self.vazia = new(antes: [], agora_do_sistema: [], agora_fatos: [], ids: [], card_em_foco_id: nil)

    def vazio?
      antes.empty? && agora_do_sistema.empty? && agora_fatos.empty?
    end
  end

  # rubocop:disable Metrics/ParameterLists
  def self.para(finalidade:, account:, conversation:, agent: nil, teto_a: 1800, teto_b: 900)
    raise ArgumentError, "finalidade desconhecida: #{finalidade}" unless FINALIDADES.include?(finalidade)
    return Leitura.vazia if conversation.nil? || conversation.account_id != account&.id || !Crm::Memoria.ativa?(conversation)

    new(account: account, conversation: conversation, agent: agent).ler(teto_a: teto_a, teto_b: teto_b)
  end
  # rubocop:enable Metrics/ParameterLists

  def initialize(account:, conversation:, agent:)
    @account = account
    @conversation = conversation
    @agent = agent
    @card = Crm::Assunto.funil_atual(conversation)
    @fuso = Crm::Timezone::Resolver.new(account: account).name_or_default
  end

  def ler(teto_a:, teto_b:)
    antes = cortar(identidade + pedidos_encerrados, teto_a)
    sistema = cortar(Crm::Memoria::Leitor::DoSistema.new(conversation: @conversation, card: @card, catalogo: catalogo).linhas, teto_b)
    fatos = cortar(fatos_de_agora, teto_b)
    Leitura.new(antes: antes, agora_do_sistema: sistema, agora_fatos: fatos, ids: (antes + fatos).filter_map(&:id).uniq,
                card_em_foco_id: @card&.id)
  end

  private

  def cortar(linhas, teto)
    usado = 0
    linhas.take_while do |linha|
      usado += Render.json_linha(linha, fuso: @fuso).length + 1
      usado <= teto
    end
  end

  def identidade
    ordenar(contato.where(tipo: 'fato').order(valido_desde: :desc).limit(MAXIMO_POR_GRUPO)).filter_map { |fato| linha_do_fato(fato) }
  end

  def pedidos_encerrados
    contato.where(tipo: 'pedido_encerrado').where('vence_em IS NULL OR vence_em > ?', Time.current).order(valido_desde: :desc)
           .limit(MAXIMO_POR_GRUPO)
           .filter_map { |fato| linha_do_fato(fato) }
  end

  # Pedido em foco (obrigatórias, depois confirmados, divergentes e alegados; decisões), conversa, outros pedidos.
  def fatos_de_agora
    do_foco = @card ? ordenar(do_card_em_foco) : []
    da_conversa = ordenar(recentes(visiveis.where(escopo: 'conversa', conversation_id: @conversation.id)))
    (do_foco + da_conversa + ordenar(recentes(outros_pedidos))).filter_map { |fato| linha_do_fato(fato) }
  end

  def outros_pedidos
    abertos = Crm::Card.where(account_id: @account.id, contact_id: @conversation.contact_id, status: :open).where.not(id: @card&.id).select(:id)
    visiveis.where(escopo: 'card', card_id: abertos)
  end

  # As chaves obrigatórias do pedido em foco sempre entram (A13), por mais antigas que sejam; o resto, os mais recentes.
  def do_card_em_foco
    escopo = visiveis.where(escopo: 'card', card_id: @card.id)
    obrigatorias = catalogo.values.select(&:obrigatoria?).map(&:chave)
    recentes(escopo.where(chave: obrigatorias)).to_a + recentes(escopo.where.not(chave: obrigatorias)).to_a
  end

  # Teto por grupo no SQL: o corte por caracteres vem depois, sobre no máximo isto.
  def recentes(escopo) = escopo.order(valido_desde: :desc).limit(MAXIMO_POR_GRUPO)

  def contato
    visiveis.where(escopo: 'contato')
  end

  # Vigentes e divergentes, da conta e do contato da conversa; nunca sugestão, nunca eco só nosso.
  def visiveis
    Crm::MemoriaFato.vivos.where(account_id: @account.id, contact_id: @conversation.contact_id, situacao: %w[vigente divergente])
                    .where.not(fonte: 'ia_nossa')
  end

  def ordenar(escopo)
    obrigatorias = catalogo.values.select(&:obrigatoria?).map(&:chave)
    escopo.to_a.sort_by do |fato|
      [obrigatorias.include?(fato.chave) ? 0 : 1, grupo_de_ordem(fato), -fato.valido_desde.to_f]
    end
  end

  def grupo_de_ordem(fato)
    return 3 if fato.situacao == 'divergente'
    return 1 if fato.tipo == 'decisao'

    fato.confirmado? ? 0 : 2
  end

  def linha_do_fato(fato)
    origem = ORIGEM_DA_FONTE[fato.fonte]
    return if origem.nil?

    Linha.new(id: fato.id, chave: fato.chave, rotulo: rotulo(fato), valor: Crm::Memoria::Normal.linha(fato.valor),
              origem: origem, em: fato.valido_desde, message_id: fato.prova_message_ids.last, card_id: fato.card_id,
              status: status_de(fato))
  end

  def status_de(fato)
    return :divergente if fato.situacao == 'divergente'

    fato.vencido? ? :vencido : :vigente
  end

  def rotulo(fato)
    definicao = catalogo.values.find { |chave| chave.chave == fato.chave && modelo_bate?(chave, fato) }
    base = definicao&.rotulo.presence || fato.chave
    fato.item_ref.present? && !fato.item_ref.start_with?('card:') ? "#{base} (#{fato.item_ref})" : base
  end

  def modelo_bate?(chave, fato)
    { 'card' => %w[card_attribute sistema], 'contato' => %w[contact_attribute sistema], 'conversa' => %w[conversation_attribute] }
      .fetch(fato.escopo).include?(chave.attribute_model)
  end

  def catalogo
    @catalogo ||= Crm::Memoria::Catalogo.da_conta(@account)
  end
end
