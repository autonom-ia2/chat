# As execuções filhas do passo "em outro registro" (G18, #2671), abertas pelo EmOutroRegistroJob: procura os registros
# da ligação, sempre dentro da conta da mãe, e abre uma filha por registro (ver EmOutroRegistro).
#
# Cada filha nasce reservada, como a da Partida, com a cadeia e a profundidade da mãe, e a primeira rodada vai para a
# fila. O registro que quem ligou não alcança é pulado, como na Partida (D5); o que já tem execução aberta desta
# automação (ou já teve uma filha deste passo, da mesma mãe) cai no índice único e também é pulado. Os pulados ficam
# numa linha só no histórico da mãe, com a conta de cada motivo. A primeira linha do histórico da filha diz de que mãe
# ela veio e, quando há, em que conversa os passos dela agem.
class Autonomia::Automacao::FilhasDoPasso
  Execucao = ::Autonomia::Automacao::Execucao
  # O filtro da ligação `cards_do_contato` e a coluna do card que ele filtra.
  FILTROS = { 'funil_id' => :pipeline_id, 'etapa_id' => :stage_id, 'situacao' => :status }.freeze

  # `ancora_id`: o id do contato de onde a procura parte; no `criado_no_passo` (G49), o do registro criado.
  def initialize(mae, passo, ancora_id)
    @mae = mae
    @passo = passo
    @ancora_id = ancora_id
    @account = mae.account
    @acesso = ::Autonomia::Automacao::Acesso.new(mae.automacao, chave_gatilho: mae.chave_gatilho)
  end

  # A conta por resultado ('abertas', 'abertas_antes', 'fora_do_alcance', 'ja_aberta'). A automação desligada (ou o
  # motor) não abre nenhuma, e a mãe registra isso.
  def abrir
    return pular_tudo unless @mae.automacao.ativa && ::Autonomia::Automacao::Motor.ligado?(@account)

    contagem = registros.each_with_object(Hash.new(0)) { |registro, conta| conta[abrir_para(registro)] += 1 }
    anotar_pulados(contagem.except('abertas', 'abertas_antes'))
    contagem
  end

  private

  def registro = @passo['registro'].to_h

  def contato = (@contato ||= @account.contacts.find_by(id: @ancora_id))

  # Um Enumerator, para os cards irem em lotes (find_each), sem teto.
  def registros
    return Array(criado) if registro['de'] == ::Autonomia::Automacao::EmOutroRegistro::CRIADO
    return [] unless contato

    case registro['de']
    when 'contato_do_campo' then [registro['usar'] == 'conversa' ? conversa_mais_recente : contato].compact
    else cards
    end
  end

  # G49: o registro que o passo criou, do tipo que esse passo cria, sempre na conta da mãe.
  def criado
    tipo = ::Autonomia::Automacao::EmOutroRegistro.alvo_do_ramo(@passo, @mae.versao.receita)
    { 'Contact' => @account.contacts, 'Crm::Card' => @account.crm_cards }[tipo]&.find_by(id: @ancora_id)
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

  # O alcance confere a conversa em que a filha vai agir (a da mãe, no card do mesmo contato): por isso a filha é montada
  # antes, e só gravada se quem ligou alcança o registro e essa conversa.
  # O registro que já tem a filha desta mãe (uma tentativa anterior do job, que caiu no meio) não conta como pulado.
  def abrir_para(alvo)
    marca = Time.current.floor(6)
    filha = montar(alvo, marca)
    return retomar(filha.evento) if Execucao.exists?(automacao_id: @mae.automacao_id, evento: filha.evento)
    return 'fora_do_alcance' unless @acesso.alcanca?(alvo, filha)

    Execucao.transaction do
      filha.save!
      anotar(filha, alvo)
    end
    ::Autonomia::Automacao::AvancarJob.perform_later(filha.id, marca.iso8601(6))
    'abertas'
  rescue ActiveRecord::RecordNotUnique
    'ja_aberta'
  end

  # A filha que a tentativa anterior gravou e não chegou a pôr na fila ainda está só reservada (due_at = travada_em; a
  # primeira rodada zera o due_at ao tomar a reserva). Vai para a fila de novo: a tomada atômica do Executor faz a rodada
  # acontecer uma vez só, mesmo que a primeira tentativa tenha enfileirado.
  def retomar(evento)
    filha = Execucao.find_by(automacao_id: @mae.automacao_id, evento: evento)
    if filha.estado == 'andando' && filha.due_at.present? && filha.due_at == filha.travada_em
      ::Autonomia::Automacao::AvancarJob.perform_later(filha.id, filha.travada_em.iso8601(6))
    end
    'abertas_antes'
  end

  def pular_tudo
    registrar_na_mae('desligada', {})
    { 'desligada' => 1 }
  end

  # Uma linha só na mãe para os registros que ficaram sem os passos, com a conta de cada motivo.
  def anotar_pulados(pulados)
    registrar_na_mae('filhas_puladas', pulados) if pulados.any?
  end

  def registrar_na_mae(motivo, dados)
    ::Autonomia::Automacao::Registro.create!(account: @account, automacao: @mae.automacao, execucao: @mae, passo: @passo['id'],
                                             resultado: 'pulado', motivo: motivo, dados: dados)
  end

  def montar(alvo, marca)
    Execucao.new(account: @account, automacao: @mae.automacao, versao: @mae.versao, alvo: alvo, chave_gatilho: @mae.chave_gatilho,
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
