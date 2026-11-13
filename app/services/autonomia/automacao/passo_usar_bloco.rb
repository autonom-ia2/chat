# O passo "usar outra automação" (#2933): ao salvar, o bloco é da conta, do mesmo tipo de alvo, sem laço nem fundo demais,
# e quem salva (ou liga) pode tudo o que os blocos alcançados fazem; ao rodar, abre a execução do bloco (ver Bloco e
# BlocoNoExecutor).
#
# O resultado de `chamar` segue o do PassoDeAcao:
# - :ok com o bloco e a execução dele (ainda fora da fila: o Executor põe na fila depois de gravar a espera da mãe);
# - :pulado `bloco_sumiu` (a automação deixou de ser bloco, ou ficou sem versão) e `bloco_de_outro_alvo` (o gatilho do
#   bloco mudou de tipo de alvo depois de a mãe salvar): a mãe segue, com o motivo no histórico;
# - :permanente `bloco_em_laco` (o bloco já está rodando acima desta execução) e `bloco_fundo_demais` (passaria de
#   Bloco::PROFUNDIDADE blocos um dentro do outro): a mãe falha, porque seguir sem o bloco faria só metade do que ela promete.
class Autonomia::Automacao::PassoUsarBloco
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  Execucao = ::Autonomia::Automacao::Execucao
  Bloco = ::Autonomia::Automacao::Bloco

  # `conferencia`: PassosNovos::Conferencia. O laço que volta à própria automação que está sendo salva é conferido pela
  # Versao, que sabe qual é ela (Bloco.laco_ao_salvar). Cada bloco alcançado é conferido como uma receita (com quem
  # salva): o bloco que ele usa passa por aqui de novo, e a cadeia acaba no laço ou no fundo antes de repetir. O passo no
  # galho de uma filha (`conferencia.dentro`) leva isso ao bloco: lá dentro também não cabe "para cada" nem "em outro
  # registro", senão um "para cada" abriria outro pelo bloco e as execuções se multiplicariam sem teto.
  def self.problemas_ao_salvar(passo, conferencia)
    id = passo['id']
    bloco = ::Autonomia::Automacao::Definicao.find_by(account_id: conferencia.conta.id, id: passo['bloco_id'], bloco: true)
    return [texto(:de_fora, passo: id)] unless bloco
    return [texto(:vazio, passo: id, bloco: bloco.nome)] unless bloco.versao_ativa
    return [texto(:outro_alvo, passo: id, bloco: bloco.nome)] if conferencia.alvo && Bloco.alvo(bloco) != conferencia.alvo

    da_cadeia(id, bloco, conferencia)
  end

  # O laço e o fundo pela cadeia das versões ativas e, de cada bloco alcançado, o que quem salva não pode fazer.
  def self.da_cadeia(id, bloco, conferencia)
    problema, = Bloco.conferir_cadeia(bloco, conferencia.conta)
    return [texto(problema, passo: id, bloco: bloco.nome, maximo: Bloco::PROFUNDIDADE)] if problema

    # No galho de uma filha, o bloco é conferido como o galho: no tipo do registro dele (`alvo:`), o que faz o "para cada"
    # e o "em outro registro" de dentro recusarem como aninhados.
    alvo = Bloco.alvo(bloco) if conferencia.dentro
    problemas = ::Autonomia::Automacao::Receita.new(
      bloco.versao_ativa.receita, conta: conferencia.conta, account_user: conferencia.account_user, alvo: alvo
    ).problemas
    problemas.any? ? [texto(:com_problema, passo: id, bloco: bloco.nome, problema: problemas.first)] : []
  end

  def self.texto(chave, **valores) = I18n.t("autonomia.automacao.receita.bloco.#{chave}", **valores)

  # A execução do bloco que a mãe chamou neste passo, sempre na conta dela; nil se ela não chamou.
  def self.filha_de(execucao, passo_id)
    id = execucao.textos.to_h["#{Bloco::CHAVE}#{passo_id}"]
    id && Execucao.find_by(id: id, account_id: execucao.account_id)
  end

  def initialize(execucao:, passo:)
    @execucao = execucao
    @passo = passo
  end

  def chamar
    bloco = ::Autonomia::Automacao::Definicao.find_by(account_id: @execucao.account_id, id: @passo['bloco_id'], bloco: true)
    return resultado(:pulado, 'bloco_sumiu') unless bloco&.versao_ativa
    return resultado(:pulado, 'bloco_de_outro_alvo') unless Bloco.alvo(bloco) == @execucao.alvo_type

    acima = Bloco.acima(@execucao)
    return resultado(:permanente, 'bloco_em_laco') if [@execucao, *acima].any? { |execucao| execucao.automacao_id == bloco.id }
    return resultado(:permanente, 'bloco_fundo_demais') if Bloco.niveis(@execucao) >= Bloco::PROFUNDIDADE

    abrir(bloco)
  end

  def enfileirar = ::Autonomia::Automacao::AvancarJob.perform_later(@filha.id, @marca.iso8601(6))

  private

  def abrir(bloco)
    @marca = Time.current.floor(6)
    Execucao.transaction do
      @filha = Execucao.create!(account: @execucao.account, automacao: bloco, versao: bloco.versao_ativa, alvo: @execucao.alvo,
                                chave_gatilho: @execucao.chave_gatilho, estado: 'andando', travada_em: @marca, due_at: @marca,
                                cadeia: @execucao.cadeia, profundidade: @execucao.profundidade, paralela: true,
                                evento: Bloco.marca(@execucao, @passo['id'], vez))
      ::Autonomia::Automacao::Registro.create!(account: @execucao.account, automacao: bloco, execucao: @filha, passo: 'inicio',
                                               resultado: 'ok', motivo: 'bloco_de',
                                               dados: { 'mae_id' => @execucao.id, 'automacao_id' => @execucao.automacao_id })
    end
    @execucao.guardar_texto!("#{Bloco::CHAVE}#{@passo['id']}", @filha.id)
    resultado(:ok, 'bloco_chamado', 'bloco_id' => bloco.id, 'filha_id' => @filha.id)
  end

  # A vez deste passo nesta execução: o laço do "decidir" (G46) pode passar por ele de novo.
  def vez = ::Autonomia::Automacao::Registro.where(execucao: @execucao, passo: @passo['id'], motivo: 'bloco_chamado').count + 1

  def resultado(tipo, motivo, dados = {}) = Resultado.new(tipo: tipo, motivo: motivo, dados: dados)
end
