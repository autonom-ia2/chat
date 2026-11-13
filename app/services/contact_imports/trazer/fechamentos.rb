# "Trazer minha lista" (#2896): quantas vezes o fechamento da conferência pode ser tentado. Um fechamento que quebra
# sempre do mesmo jeito (ou derruba o processo) voltaria para a fila para sempre, pela repetição do job ou pela
# varredura (ContactImports::Trazer::ConferenciasParadas), e a tela mostraria "trazendo" sem fim.
#
# - `comecar` conta a tentativa ANTES de ela rodar, numa transação própria: a tentativa que derruba o processo também
#   fica contada. Só um número é guardado (options['trazer']['fechamentos']).
# - Na tentativa de número TETO que não termina, a importação vira `failed` com o código `fechamento` em
#   validation_summary['import_error'] (nunca a mensagem do erro): a tela mostra "falhou" e "Tentar de novo".
# - "Tentar de novo" (Relacionamentos::Trazer::Trazer) recomeça a contagem.
# - `sem_arquivo`: o fechamento que não tem de onde ler desiste na hora, com o mesmo código. Repetir não adiantaria.
# - `desligada`: a importação de planilhas foi desligada na instalação entre o clique e o job. Nada fecharia nem
#   gravaria a lista; ela falha na hora, com o mesmo código, em vez de a tela mostrar "trazendo" sem fim.
#
# O fechamento roda inteiro numa transação: o que quebrou não deixa nada pela metade, e tentar de novo parte do mesmo
# ponto.
class ContactImports::Trazer::Fechamentos
  CHAVE = 'fechamentos'.freeze
  ERRO = 'fechamento'.freeze
  TETO = 3

  # A lista parou porque o fechamento desistiu (e não porque a gravação quebrou no meio).
  def self.desistiu?(importacao)
    importacao.failed? && importacao.import_started_at.nil? && importacao.validation_summary.to_h['import_error'] == ERRO
  end

  def initialize(importacao)
    @importacao = importacao
  end

  # Devolve se o fechamento deve rodar agora.
  def comecar
    @importacao.with_lock do
      next false unless @importacao.confirmed?
      next desistir if conferencia.fechamentos >= TETO

      conferencia.gravar(CHAVE => conferencia.fechamentos + 1)
      true
    end
  end

  # A tentativa não terminou. Na última, a importação deixa de esperar por um fechamento que não vem.
  def nao_terminou
    @importacao.with_lock { desistir if @importacao.confirmed? && conferencia.fechamentos >= TETO }
  end

  def terminou
    conferencia.tirar(CHAVE)
  end

  # Devolve verdadeiro: a tentativa está encerrada, e a lista (se ainda esperava o fechamento) falhou.
  def sem_arquivo
    desistir_se_ainda_espera
    true
  end

  def desligada
    desistir_se_ainda_espera
  end

  # Sob a trava de quem chama: a lista volta a poder ser fechada, com a contagem do começo.
  def recomecar
    conferencia.tirar(CHAVE)
    resumo = @importacao.validation_summary.to_h
    @importacao.update!(validation_summary: resumo.except('import_error')) if resumo['import_error'] == ERRO
  end

  private

  def desistir_se_ainda_espera
    @importacao.with_lock { desistir if @importacao.confirmed? }
  end

  def desistir
    @importacao.update!(status: :failed, validation_summary: @importacao.validation_summary.to_h.merge('import_error' => ERRO))
    Rails.logger.warn("[ContactImports::Trazer::Fechamentos] import_id=#{@importacao.id} gave up")
    false
  end

  def conferencia
    ContactImports::Trazer::Conferencia.new(@importacao)
  end
end
