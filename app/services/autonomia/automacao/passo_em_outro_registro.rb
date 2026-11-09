# O passo "em outro registro" (G18, #2671) na rodada da mãe: lê a âncora da ligação no alvo de agora e entrega o resto
# ao EmOutroRegistroJob, que procura os registros e abre uma execução filha por registro (ver EmOutroRegistro). A mãe
# não espera as filhas nem prende o worker procurando: segue para o passo seguinte.
#
# O resultado segue o do PassoDeAcao:
# - :ok com a ligação nos dados (a procura e as filhas ficam com o job);
# - :pulado `faltou_valor` sem âncora (o campo do card vazio, o alvo sem contato);
# - :pulado `campo_nao_e_contato` quando o campo da ligação deixou de ser do tipo contato depois de a automação ligar
#   (decisão 16): o número que ele guarda agora é de outra coisa, e a mensagem iria a outro cliente;
# - :sem_acesso `sem_chave_de_funis` quando a ligação lê cards e quem ligou perdeu a chave de funis: pausa, como a ação
#   de funil (#2633).
class Autonomia::Automacao::PassoEmOutroRegistro
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado

  def initialize(execucao:, passo:, valores:, acesso:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @acesso = acesso
  end

  def executar
    # A filha nunca abre netas: o salvar já recusa "em outro registro" dentro de outro, e a rodada confere de novo.
    return Resultado.new(tipo: :pulado, motivo: 'receita_com_problema', dados: {}) if ::Autonomia::Automacao::EmOutroRegistro.da(@execucao)
    return Resultado.new(tipo: :sem_acesso, motivo: 'sem_chave_de_funis', dados: {}) if sem_chave?
    return Resultado.new(tipo: :pulado, motivo: 'campo_nao_e_contato', dados: {}) unless campo_de_contato?

    # Só um número inteiro de verdade: "12abc" não vira o contato 12.
    contato_id = Integer(ancora.to_s, 10, exception: false).to_i
    return Resultado.new(tipo: :pulado, motivo: 'faltou_valor', dados: {}) unless contato_id.positive?

    ::Autonomia::Automacao::EmOutroRegistroJob.perform_later(@execucao.account_id, @execucao.id, @passo['id'], contato_id)
    Resultado.new(tipo: :ok, dados: { 'ligacao' => registro['de'], 'contato_id' => contato_id })
  end

  private

  def registro = @passo['registro'].to_h

  def sem_chave?
    ::Autonomia::Automacao::EmOutroRegistro.de_funil?(@passo) && !::Autonomia::Automacao::RegraDoFunil.chave?(@acesso.account_user)
  end

  # Conferido a cada rodada, não só ao salvar: o tipo do campo pode ter mudado depois de a automação ligar.
  def campo_de_contato?
    return true unless registro['de'] == 'contato_do_campo'

    ::Autonomia::Automacao::EmOutroRegistro.campo_do_contato?(registro.dig('campo', '$valor').to_s, @execucao.account)
  end

  # O contato de onde a procura parte: o do campo (`contato_do_campo`) ou o do alvo (`cards_do_contato`).
  def ancora
    return @valores.ler(registro.dig('campo', '$valor')) if registro['de'] == 'contato_do_campo'

    @valores.ler('contato.id')
  end
end
