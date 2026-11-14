# "Trazer minha lista" (#2896): quem entra se a pessoa mandar trazer agora. É a ÚNICA conta: a tela a mostra
# (`contas`, em Relacionamentos::Trazer::Leitura e Relacionamentos::Trazer::MudarLinha), o "Trazer" a usa para saber se há alguém
# (Relacionamentos::Trazer::Trazer) e o fechamento da conferência grava exatamente estas linhas
# (ContactImports::Trazer::FecharConferencia).
#
# - Entram as linhas aprovadas na leitura e as `novas`: as consertadas por inteiro, que ainda são problema no banco e
#   que a pessoa não deixou de fora.
# - A linha repetida que a pessoa escolheu manter tira do lugar a outra linha da mesma pessoa (`trocadas`). A trocada
#   não entra nem quando ela mesma tinha sido consertada: de um grupo de linhas da mesma pessoa entra uma só.
#
# - Das que entram, `sem_telefone` conta as que ficam sem o telefone que estava escrito na planilha: o número não deu
#   para ler como celular e a linha entra pelo e-mail. É a fonte única desse número, sempre sobre quem entra de fato:
#   a linha aprovada que saiu no lugar de uma repetida não conta, e a consertada que entra sem telefone conta.
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

  # Quantas das que entram ficam sem o telefone que estava escrito na planilha. Na linha aprovada, a leitura deixou o
  # telefone sem resumo e a máscara do que estava na célula (vazia quando a célula não tinha número nenhum). Na linha
  # consertada, quem diz é o conserto (ContactImports::Trazer::Conserto), que guarda só a marca.
  def sem_telefone
    return 0 unless @importacao.normalized_csv.attached?

    aprovadas = linhas.status_valid.where.not(row_number: trocadas).where(normalized_phone_hash: nil).where.not(raw_phone_masked: [nil, ''])
    aprovadas.count + guardadas.except(*trocadas).count { |_numero, feito| feito['sem_telefone'] }
  end

  # O que a tela mostra de quem entra: quantas pessoas, quantas delas como cliente, com a resposta de agora
  # (ContactImports::Trazer::Cliente#quantas), e quantas sem o telefone da planilha. São as mesmas contas no resumo da
  # leitura e na resposta de quem mexe numa linha.
  def contas
    { entram: quantas, clientes: ContactImports::Trazer::Cliente.new(@importacao).quantas(self), semTelefone: sem_telefone }
  end

  # { o que a linha tem nesta coluna (pela chave em extra_values; nil na vazia) => quantas das que entram }, numa
  # consulta só: é com isto que se conta quem entra como cliente (ContactImports::Trazer::Cliente#quantas).
  def por_valor(chave)
    return {} unless @importacao.normalized_csv.attached?

    entram = linhas.status_valid.where.not(row_number: trocadas).or(linhas.where(row_number: novas.keys))
    entram.group(ContactImports::Trazer::ValoresDeCliente.celula(chave)).count
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
