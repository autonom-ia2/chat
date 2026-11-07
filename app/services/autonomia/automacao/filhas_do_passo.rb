# As execuções filhas do passo "em outro registro" (G18, #2671), abertas pelo EmOutroRegistroJob: procura os registros
# da ligação, sempre dentro da conta da mãe, e abre uma filha por registro (ver EmOutroRegistro).
#
# Cada filha nasce reservada, como a da Partida, com a cadeia e a profundidade da mãe, e a primeira rodada vai para a
# fila. O registro que quem ligou não alcança é pulado, como na Partida (D5); o que já tem execução aberta desta
# automação (ou já teve uma filha deste passo, da mesma mãe) cai no índice único e também é pulado. A primeira linha do
# histórico da filha diz de que mãe ela veio e, quando há, em que conversa os passos dela agem.
class Autonomia::Automacao::FilhasDoPasso
  Execucao = ::Autonomia::Automacao::Execucao
  # O filtro da ligação `cards_do_contato` e a coluna do card que ele filtra.
  FILTROS = { 'funil_id' => :pipeline_id, 'etapa_id' => :stage_id, 'situacao' => :status }.freeze

  def initialize(mae, passo, contato_id)
    @mae = mae
    @passo = passo
    @contato_id = contato_id
    @account = mae.account
    @acesso = ::Autonomia::Automacao::Acesso.new(mae.automacao, chave_gatilho: mae.chave_gatilho)
  end

  # Quantas filhas abriu. A automação desligada (ou o motor) não abre nenhuma.
  def abrir
    return 0 unless @mae.automacao.ativa && ::Autonomia::Automacao::Motor.ligado?(@account)

    registros.count { |registro| abrir_para(registro) }
  end

  private

  def registro = @passo['registro'].to_h

  def contato = (@contato ||= @account.contacts.find_by(id: @contato_id))

  # Um Enumerator, para os cards irem em lotes (find_each), sem teto.
  def registros
    return [] unless contato

    case registro['de']
    when 'contato_do_campo' then [registro['usar'] == 'conversa' ? conversa_mais_recente : contato].compact
    else cards
    end
  end

  def conversa_mais_recente
    @account.conversations.where(contact_id: contato.id).order(last_activity_at: :desc, id: :desc).first
  end

  def cards
    filtros = FILTROS.filter_map { |chave, coluna| [coluna, registro[chave]] if registro[chave].present? }.to_h
    escopo = @account.crm_cards.where(contact_id: contato.id, **filtros).where.not(id: card_da_mae)
    return Array(escopo.order(created_at: :desc, id: :desc).first) if registro['mais_recente']

    escopo.find_each
  end

  # O próprio alvo da mãe não é "outro registro".
  def card_da_mae = (@mae.alvo_id if @mae.alvo_type == 'Crm::Card')

  def abrir_para(alvo)
    return false unless @acesso.alcanca?(alvo)

    marca = Time.current.floor(6)
    filha = criar(alvo, marca)
    anotar(filha, alvo)
    ::Autonomia::Automacao::AvancarJob.perform_later(filha.id, marca.iso8601(6))
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def criar(alvo, marca)
    Execucao.create!(account: @account, automacao: @mae.automacao, versao: @mae.versao, alvo: alvo, chave_gatilho: @mae.chave_gatilho,
                     estado: 'andando', travada_em: marca, due_at: marca, cadeia: @mae.cadeia, profundidade: @mae.profundidade,
                     evento: ::Autonomia::Automacao::EmOutroRegistro.marca(@mae, alvo, @passo['id']))
  end

  # "Registre no histórico qual conversa foi usada" (Automação, 07/11): a da mãe ou a do próprio registro.
  def anotar(filha, alvo)
    da_mae = ::Autonomia::Automacao::EmOutroRegistro.conversa_da_mae(filha, alvo) if alvo.is_a?(::Crm::Card)
    conversa = da_mae || ::Autonomia::Automacao::Contexto.de(alvo).conversa
    de_quem = da_mae ? 'mae' : 'registro'
    dados = { 'mae_id' => @mae.id, 'conversa_id' => conversa&.display_id, 'conversa_de' => (de_quem if conversa) }.compact
    ::Autonomia::Automacao::Registro.create!(account: @account, automacao: @mae.automacao, execucao: filha, passo: 'inicio', resultado: 'ok',
                                             motivo: 'em_outro_registro', dados: dados)
  end
end
