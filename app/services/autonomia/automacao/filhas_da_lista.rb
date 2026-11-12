# As execuções filhas do passo "para cada um de uma lista" (#2932), abertas pelo RepetirListaJob (ver RepetirLista).
#
# Na ordem da lista, até o teto do passo (no máximo RepetirLista::TETO_MAXIMO por vez). Cada item:
# - que já ganhou a filha desta rodada (uma tentativa anterior do job, que caiu no meio) conta como aberto e não abre de
#   novo (`abertas_antes`): a rodada retoma de onde parou;
# - que já está no meio desta automação fica de fora (`ja_aberta`), como o índice das abertas garante;
# - que recusa mensagens ativas ou está bloqueado (relido agora) fica de fora (`bloqueados`);
# - que quem ligou não alcança fica de fora (`fora_do_alcance`), como na Partida (D5);
# - ganha a filha. Ritmo `rapido`: todas vão para a fila agora. `aos_poucos`: a primeira agora e cada uma das seguintes
#   um minuto depois da anterior, esperando no banco (a varredura acorda).
# A mãe ganha uma linha só no histórico, com a conta de cada resultado e quantos ficaram para a próxima vez (`passou_do_teto`,
# sem os bloqueados, quem já está no meio nem quem quem ligou não alcança).
#
# A lista pode ser grande (uma etiqueta com milhares de contatos). Por lote, numa consulta cada: as filhas desta rodada,
# quem já está no meio e quem recusa. Só o alcance pergunta item a item (as políticas), e essa pergunta tem teto:
# `teto + ItensDaLista::ALEM_DO_TETO` por rodada; passou dele, a rodada para de ler (o que ficou entra na próxima vez).
#
# Sem a flag dos passos novos (rollback) não abre nada, nem com o job já na fila.
class Autonomia::Automacao::FilhasDaLista
  Execucao = ::Autonomia::Automacao::Execucao
  ItensDaLista = ::Autonomia::Automacao::ItensDaLista
  RITMO = 1.minute
  LOTE = 100
  # Todas as contas sempre no registro: o texto do histórico (motivos.lista_rodou) lê cada uma.
  CONTAGENS = %w[abertas abertas_antes bloqueados fora_do_alcance ja_aberta passou_do_teto].freeze

  def initialize(mae, passo)
    @mae = mae
    @passo = passo
    @account = mae.account
    @acesso = ::Autonomia::Automacao::Acesso.new(mae.dona, chave_gatilho: mae.chave_gatilho)
  end

  def abrir
    return anotar('passos_novos_desligados', {}) unless ::Autonomia::Automacao::PassosNovos.ligados?(@account)
    return anotar('desligada', {}) unless @mae.dona.ativa && ::Autonomia::Automacao::Motor.ligado?(@account)

    @contagem = Hash.new(0)
    @abertas = 0
    @perguntas = 0
    itens.find_in_batches(batch_size: LOTE) do |lote|
      percorrer(lote)
      break if sem_perguntas?
    end
    anotar('lista_rodou', CONTAGENS.index_with(0).merge(@contagem, 'teto' => teto))
  end

  private

  def teto = @passo['teto'].to_i.clamp(1, ::Autonomia::Automacao::RepetirLista::TETO_MAXIMO)

  def sem_perguntas? = @perguntas >= teto + ItensDaLista::ALEM_DO_TETO

  # Em lotes pelo id (find_in_batches), a mesma ordem da lista.
  def itens = ItensDaLista.new(@account, @passo['lista']).escopo.unscope(:order)

  def percorrer(lote)
    @desta_rodada = eventos_desta_rodada(lote)
    @no_meio = no_meio(lote)
    @recusados = ItensDaLista.recusados(lote)
    lote.each do |item|
      break if sem_perguntas?

      motivo = @abertas >= teto ? depois_do_teto(item) : abrir_para(item)
      @contagem[motivo] += 1 if motivo
    end
  end

  # As marcas das filhas que esta rodada já abriu, entre as do lote.
  def eventos_desta_rodada(lote)
    marcas = lote.map { |item| ::Autonomia::Automacao::RepetirLista.marca(@mae, item, @passo['id']) }
    Execucao.where(account_id: @account.id, automacao_id: @mae.automacao_id, evento: marcas).pluck(:evento).to_set
  end

  # Os itens do lote com uma execução aberta desta automação: a mesma régua do índice das abertas (sem as paralelas).
  def no_meio(lote)
    Execucao.abertas.where(account_id: @account.id, automacao_id: @mae.automacao_id, paralela: false, chave_gatilho: @mae.chave_gatilho,
                           alvo_type: lote.first.class.polymorphic_name, alvo_id: lote.map(&:id)).pluck(:alvo_id).to_set
  end

  def recusado?(item) = @recusados.include?(ItensDaLista.contato_de(item)&.id)

  def alcanca?(item, filha = nil)
    @perguntas += 1
    @acesso.alcanca?(item, filha)
  end

  # Depois do teto, só a conta dos que entrariam na próxima vez.
  def depois_do_teto(item)
    return if @no_meio.include?(item.id) || recusado?(item)

    'passou_do_teto' if alcanca?(item)
  end

  def abrir_para(item)
    marca = Time.current.floor(6)
    filha = montar(item, marca)
    return retomar(filha.evento) if @desta_rodada.include?(filha.evento)
    return 'ja_aberta' if @no_meio.include?(item.id)
    return 'bloqueados' if recusado?(item)
    return 'fora_do_alcance' unless alcanca?(item, filha)

    gravar(filha, marca)
  rescue ActiveRecord::RecordNotUnique
    'ja_aberta'
  end

  # A primeira (e todas, no ritmo rápido) vai para a fila agora; as seguintes esperam no banco, um minuto cada.
  def gravar(filha, marca)
    espera = @passo['ritmo'] == 'rapido' ? 0 : @abertas
    filha.assign_attributes(estado: 'esperando', travada_em: nil, due_at: marca + (espera * RITMO)) if espera.positive?
    Execucao.transaction do
      filha.save!
      ::Autonomia::Automacao::Registro.create!(account: @account, automacao: @mae.automacao, execucao: filha, passo: 'inicio',
                                               resultado: 'ok', motivo: 'repetir_lista', dados: { 'mae_id' => @mae.id })
    end
    ::Autonomia::Automacao::AvancarJob.perform_later(filha.id, marca.iso8601(6)) unless espera.positive?
    @abertas += 1
    'abertas'
  end

  # A filha que a tentativa anterior gravou e não chegou a pôr na fila ainda está só reservada: vai para a fila de novo
  # (a tomada atômica do Executor faz a rodada acontecer uma vez só). A que espera no banco a varredura acorda.
  def retomar(evento)
    filha = Execucao.find_by(account_id: @account.id, automacao_id: @mae.automacao_id, evento: evento)
    if filha.estado == 'andando' && filha.due_at.present? && filha.due_at == filha.travada_em
      ::Autonomia::Automacao::AvancarJob.perform_later(filha.id, filha.travada_em.iso8601(6))
    end
    @abertas += 1
    'abertas_antes'
  end

  def montar(item, marca)
    Execucao.new(account: @account, automacao: @mae.automacao, versao: @mae.versao, alvo: item, chave_gatilho: @mae.chave_gatilho,
                 estado: 'andando', travada_em: marca, due_at: marca, cadeia: @mae.cadeia, profundidade: @mae.profundidade,
                 evento: ::Autonomia::Automacao::RepetirLista.marca(@mae, item, @passo['id']))
  end

  def anotar(motivo, contagem)
    ::Autonomia::Automacao::Registro.create!(account: @account, automacao: @mae.automacao, execucao: @mae, passo: @passo['id'],
                                             resultado: motivo == 'lista_rodou' ? 'ok' : 'pulado', motivo: motivo, dados: contagem)
    contagem
  end
end
