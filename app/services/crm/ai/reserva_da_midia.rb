# A trava de um anexo durante a leitura paga (Crm::Ai::LeitorDeMidia e o turno dos Agentes IA, #2109 e #2141). A leitura
# leva de segundos a minutos (download, transcrição, visão com novas tentativas); segurar o FOR UPDATE e a transação
# aberta esse tempo todo prende o vacuum e faz quem espera a mesma linha estourar o statement_timeout. Então:
#   1. trava curta: confere se o anexo ainda é para ler, marca "em leitura" (`crm_ai_midia_lendo_ate`, com PRAZO) com o
#      dono da marca (`crm_ai_midia_lendo_dono`, um token aleatório), e solta;
#   2. a leitura roda fora de transação;
#   3. trava curta: grava o resultado sobre o meta ATUAL (o que outro processo escreveu no meio não se perde) e tira a
#      marca, só se ela ainda for de quem grava (#2141). Quem demorou mais que o PRAZO e perdeu a marca para outro
#      processo grava o resultado, mas deixa a marca do outro: sem isso, um terceiro reservaria e pagaria de novo.
#
# O prazo é contado no relógio do banco (#2141): quem marca e quem confere a marca na reserva usam o mesmo relógio, e
# dois processos com relógios levemente diferentes não discordam na fronteira do prazo. Fora da reserva, `lendo?` só
# decide se vale esperar o texto, e usa o relógio do processo.
#
# Processo que morre no meio: no desligamento do Sidekiq (deploy), o `Sidekiq::Shutdown` passa pelo `ensure` de quem
# leu, que libera a marca. Um processo morto sem aviso (OOM, kill -9) deixa a marca, que vence no PRAZO: o anexo volta
# a ser lido.
#
# Quem precisa do texto agora (a leitura em linha da IA de assunto, o turno dos Agentes IA) e encontra o anexo em
# leitura espera um pouco (`esperar`), em vez de pagar de novo.
class Crm::Ai::ReservaDaMidia
  LENDO = 'crm_ai_midia_lendo_ate'.freeze
  DONO = 'crm_ai_midia_lendo_dono'.freeze
  # Maior que a leitura mais lenta: a visão faz até 3 chamadas de 180 s; a transcrição, 120 s mais o download.
  PRAZO = 10.minutes
  ESPERA_EM_LINHA = 20.seconds
  INTERVALO_DA_ESPERA = 0.5

  def self.lendo?(meta, agora = Time.current)
    ate = meta[LENDO].presence
    ate.present? && Time.zone.parse(ate.to_s)&.after?(agora) == true
  end

  # Trava curta. O bloco diz se o anexo ainda é para ler (roda com o registro recarregado). -> o token do dono quando
  # reservou; nil quando não.
  def self.reservar(attachment)
    attachment.with_lock do
      agora = relogio_do_banco
      next if lendo?(attachment.meta.to_h, agora) || !yield

      ate = (agora + PRAZO).iso8601(6)
      dono = "#{ate}/#{SecureRandom.uuid}"
      attachment.update!(meta: attachment.meta.to_h.merge(LENDO => ate, DONO => dono))
      dono
    end
  end

  # Trava curta. O bloco recebe o meta atual, sem a marca, e devolve o meta a gravar. A marca sai só quando é de `dono`;
  # a de outro processo fica como está.
  def self.gravar(attachment, dono:)
    attachment.with_lock do
      atual = attachment.meta.to_h
      marca = minha?(atual, dono) ? {} : atual.slice(LENDO, DONO)
      attachment.update!(meta: yield(atual.except(LENDO, DONO)).merge(marca))
    end
  end

  # O token do dono carrega o prazo que ele marcou: no deploy, o código anterior (sem dono) reserva regravando só o
  # prazo, e a marca dele não pode passar por minha.
  def self.minha?(meta, dono)
    meta[DONO] == dono && meta[LENDO] == dono.to_s.split('/', 2).first
  end
  private_class_method :minha?

  def self.liberar(attachment, dono:) = gravar(attachment, dono: dono) { |meta| meta }

  # Outro processo está lendo o anexo: espera o resultado até `ate_em`. -> o anexo, recarregado.
  def self.esperar(attachment, ate_em: ESPERA_EM_LINHA.from_now)
    sleep(INTERVALO_DA_ESPERA) while lendo?(attachment.reload.meta.to_h) && Time.current < ate_em
    attachment
  end

  # Dentro da transação da trava: clock_timestamp() é a hora real do banco (now() é a do início da transação).
  def self.relogio_do_banco
    Time.zone.parse(Attachment.connection.select_value('SELECT clock_timestamp()').to_s)
  end
  private_class_method :relogio_do_banco
end
