# A trava de um anexo durante a leitura do Crm::Ai::LeitorDeMidia (#2109, revisão de banco). A leitura paga leva de
# segundos a minutos (download, transcrição, visão com novas tentativas); segurar o FOR UPDATE e a transação aberta esse
# tempo todo prende o vacuum e faz quem espera a mesma linha estourar o statement_timeout. Então:
#   1. trava curta: confere se o anexo ainda é para ler, marca "em leitura" (`crm_ai_midia_lendo_ate`, com PRAZO) e solta;
#   2. a leitura roda fora de transação;
#   3. trava curta: grava o resultado sobre o meta ATUAL (o que outro processo escreveu no meio não se perde) e tira a
#      marca.
# Processo que morre no meio deixa a marca, que vence no PRAZO: o anexo volta a ser lido.
#
# Quem precisa do texto agora (a leitura em linha da IA de assunto, o turno dos Agentes IA) e encontra o anexo em
# leitura espera um pouco (`esperar`), em vez de pagar de novo.
class Crm::Ai::ReservaDaMidia
  LENDO = 'crm_ai_midia_lendo_ate'.freeze
  # Maior que a leitura mais lenta: a visão faz até 3 chamadas de 180 s; a transcrição, 120 s mais o download.
  PRAZO = 10.minutes
  ESPERA_EM_LINHA = 20.seconds
  INTERVALO_DA_ESPERA = 0.5

  def self.lendo?(meta)
    ate = meta[LENDO].presence
    ate.present? && Time.zone.parse(ate.to_s)&.future? == true
  end

  # Trava curta. O bloco diz se o anexo ainda é para ler (roda com o registro recarregado). -> true quando reservou.
  def self.reservar(attachment)
    attachment.with_lock do
      next false if lendo?(attachment.meta.to_h) || !yield

      attachment.update!(meta: attachment.meta.to_h.merge(LENDO => PRAZO.from_now.iso8601))
      true
    end
  end

  # Trava curta. O bloco recebe o meta atual, sem a marca, e devolve o meta a gravar.
  def self.gravar(attachment)
    attachment.with_lock { attachment.update!(meta: yield(attachment.meta.to_h.except(LENDO))) }
  end

  def self.liberar(attachment) = gravar(attachment) { |meta| meta }

  # Outro processo está lendo o anexo: espera o resultado até `ate_em`. -> o anexo, recarregado.
  def self.esperar(attachment, ate_em: ESPERA_EM_LINHA.from_now)
    sleep(INTERVALO_DA_ESPERA) while lendo?(attachment.reload.meta.to_h) && Time.current < ate_em
    attachment
  end
end
