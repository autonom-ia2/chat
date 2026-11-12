# As execuções filhas do passo "para cada um de uma lista" (#2932), abertas pelo RepetirListaJob (ver RepetirLista).
#
# Na ordem da lista, até o teto do passo (no máximo RepetirLista::TETO_MAXIMO por vez). Cada item:
# - que recusa mensagens ativas ou está bloqueado (relido agora) fica de fora (`bloqueados`);
# - que quem ligou não alcança fica de fora (`fora_do_alcance`), como na Partida (D5);
# - que já está no meio desta automação cai no índice das abertas (`ja_aberta`);
# - que já ganhou a filha desta rodada (uma tentativa anterior do job, que caiu no meio) conta como aberto e não abre de
#   novo (`abertas_antes`): a rodada retoma de onde parou;
# - ganha a filha. Ritmo `rapido`: todas vão para a fila agora. `aos_poucos`: a primeira agora e cada uma das seguintes
#   um minuto depois da anterior, esperando no banco (a varredura acorda).
# A mãe ganha uma linha só no histórico, com a conta de cada resultado e quantos ficaram para a próxima vez (`passou_do_teto`,
# sem os bloqueados nem quem quem ligou não alcança).
class Autonomia::Automacao::FilhasDaLista
  Execucao = ::Autonomia::Automacao::Execucao
  RITMO = 1.minute
  # Todas as contas sempre no registro: o texto do histórico (motivos.lista_rodou) lê cada uma.
  CONTAGENS = %w[abertas abertas_antes bloqueados fora_do_alcance ja_aberta passou_do_teto].freeze

  def initialize(mae, passo)
    @mae = mae
    @passo = passo
    @account = mae.account
    @acesso = ::Autonomia::Automacao::Acesso.new(mae.dona, chave_gatilho: mae.chave_gatilho)
  end

  def abrir
    return anotar('desligada', {}) unless @mae.dona.ativa && ::Autonomia::Automacao::Motor.ligado?(@account)

    contagem = Hash.new(0)
    @abertas = 0
    itens.find_each do |item|
      break contagem['passou_do_teto'] = restantes(item) if @abertas >= teto

      contagem[abrir_para(item)] += 1
    end
    anotar('lista_rodou', CONTAGENS.index_with(0).merge(contagem, 'teto' => teto))
  end

  private

  def teto = @passo['teto'].to_i.clamp(1, ::Autonomia::Automacao::RepetirLista::TETO_MAXIMO)

  # Os que entrariam na próxima vez, pela régua da contagem da tela (ItensDaLista#contar): sem o bloqueado nem quem
  # quem ligou não alcança, lidos até ItensDaLista::LEITURA_DA_CONTAGEM.
  def restantes(primeiro)
    itens.where(id: primeiro.id..).order(:id).limit(::Autonomia::Automacao::ItensDaLista::LEITURA_DA_CONTAGEM).count do |item|
      !::Autonomia::Automacao::ItensDaLista.recusado?(item, relido: false) && @acesso.alcanca?(item)
    end
  end

  # Em lotes pelo id (find_each), a mesma ordem da lista.
  def itens = ::Autonomia::Automacao::ItensDaLista.new(@account, @passo['lista']).escopo.unscope(:order)

  def abrir_para(item)
    marca = Time.current.floor(6)
    filha = montar(item, marca)
    return retomar(filha.evento) if Execucao.exists?(account_id: @account.id, automacao_id: @mae.automacao_id, evento: filha.evento)
    return 'bloqueados' if ::Autonomia::Automacao::ItensDaLista.recusado?(item)
    return 'fora_do_alcance' unless @acesso.alcanca?(item, filha)

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
