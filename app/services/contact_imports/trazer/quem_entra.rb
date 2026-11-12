# "Trazer minha lista" (#2896): quem entra se a pessoa mandar trazer agora. É a ÚNICA conta: a tela a mostra
# (Relacionamentos::Trazer::Leitura, Relacionamentos::Trazer::MudarLinha), o "Trazer" a usa para saber se há alguém
# (Relacionamentos::Trazer::Trazer) e o fechamento da conferência grava exatamente estas linhas
# (ContactImports::Trazer::FecharConferencia).
#
# - Entram as linhas aprovadas na leitura e as `novas`: as consertadas por inteiro, que ainda são problema no banco e
#   que a pessoa não deixou de fora.
# - A linha repetida que a pessoa escolheu manter tira do lugar a outra linha da mesma pessoa (`trocadas`). A trocada
#   não entra nem quando ela mesma tinha sido consertada: de um grupo de linhas da mesma pessoa entra uma só.
#
# Recebe os consertos já lidos ({ número => o que o arquivo guarda }): quem chama leu o arquivo uma vez.
class ContactImports::Trazer::QuemEntra
  def initialize(importacao, consertos)
    @importacao = importacao
    @consertos = consertos
  end

  # { número => a linha conferida } das linhas consertadas que vão entrar.
  def novas
    @novas ||= guardadas.except(*trocadas).transform_values { |feito| feito['conferida'] }
  end

  # Os números das linhas que saem no lugar de uma repetida que a pessoa manteve.
  def trocadas
    @trocadas ||= guardadas.values.filter_map { |feito| feito['outra'] }.uniq
  end

  # Sem o arquivo conferido (apagado pelo prazo) não há de onde tirar quem entra.
  def quantas
    return 0 unless @importacao.normalized_csv.attached?

    @importacao.valid_rows + novas.size - linhas.status_valid.where(row_number: trocadas).count
  end

  private

  def guardadas
    @guardadas ||= begin
      conferidas = @consertos.select { |_numero, feito| feito['conferida'].present? }
      com_problema = linhas.status_invalid.where(row_number: conferidas.keys).pluck(:row_number)
      conferidas.slice(*(com_problema - ContactImports::Trazer::Conferencia.new(@importacao).deixadas))
    end
  end

  def linhas
    @importacao.campaign_import_rows
  end
end
