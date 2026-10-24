# IA entende a conversa, F4: lê os anexos da mensagem nova na chegada (Crm::Ai::LeitorDeMidia), na fila high, para o
# texto estar pronto quando a IA de assunto perguntar. Sem a flag, não faz nada. A varredura da mídia pendente
# (Crm::Ai::RelerMidiaPendenteJob) também usa este job, para as mensagens dos últimos 2 dias.
#
# O job roda no commit da mensagem, e o upload do anexo para o storage pode ainda não ter terminado. Arquivo ausente:
# tenta de novo com espera crescente (2 s, 4 s, ... 128 s; uns 4 minutos ao todo). Na última tentativa, o leitor marca
# o anexo como lido sem texto (`arquivo_ausente`), com aviso no log.
#
# Falha passageira da API da IA (rede, tempo esgotado, 429, 5xx, credencial recusada; #2109): o leitor deixa o anexo
# pendente e agenda a próxima tentativa nele; aqui, tenta de novo com as duas primeiras esperas do leitor (1 e 5 min).
# Depois disso, quem tenta é a varredura, enquanto a mensagem tiver até Crm::Ai::FalhaDaMidia::JANELA_DE_RELEITURA (só a
# mensagem do cliente; a da equipe a varredura não relê, e o log diz isso).
#
# A releitura (`releitura` 'mensagem_nova' ou 'varredura') não tenta de novo aqui: faz uma chamada só por anexo, com o
# tempo da chegada, para no primeiro erro passageiro, e a nova tentativa é a próxima releitura.
class Crm::Ai::LerMidiaJob < ApplicationJob
  TENTATIVAS = 8
  TENTATIVAS_DA_FALHA_PASSAGEIRA = 3

  # A releitura (mensagem nova ou varredura) não disputa a fila high com a entrega de mensagens: a leitura paga pode levar
  # minutos. E uma mensagem entra no máximo uma vez a cada DEDUP_DA_RELEITURA: fila atrasada não empilha a mesma.
  FILA_DA_RELEITURA = :low
  DEDUP_DA_RELEITURA = 30.minutes

  queue_as :high
  retry_on ActiveStorage::FileNotFoundError, attempts: TENTATIVAS, wait: ->(executions) { 2**executions }
  retry_on Crm::Ai::LeitorDeMidia::FalhaPassageira,
           attempts: TENTATIVAS_DA_FALHA_PASSAGEIRA,
           wait: ->(executions) { Crm::Ai::FalhaDaMidia::ESPERAS.fetch(executions - 1) } do |job, erro|
    job.avisar_desistencia(erro)
  end

  # `releitura`: 'mensagem_nova' (a leitura em linha) ou 'varredura' (Crm::Ai::RelerMidiaPendenteJob).
  # -> true quando enfileirou.
  def self.reler(message_id, releitura)
    return false unless Redis::Alfred.set("crm:leitor_de_midia:releitura:#{message_id}", 1, nx: true, ex: DEDUP_DA_RELEITURA.to_i)

    set(queue: FILA_DA_RELEITURA).perform_later(message_id, releitura)
    true
  end

  # Sem `releitura`: a leitura da chegada (seleção do modo mensagem nova, com as novas tentativas de sempre).
  def perform(message_id, releitura = nil)
    message = Message.find_by(id: message_id)
    return if message.blank?

    Crm::Ai::LeitorDeMidia.new(message, ultima_tentativa: executions >= TENTATIVAS, releitura: (releitura || 'mensagem_nova').to_sym,
                                        uma_chamada: releitura.present?).perform
  rescue Crm::Ai::LeitorDeMidia::FalhaPassageira => e
    raise if releitura.blank?

    Rails.logger.info("[crm][midia] releitura_falhou_fica_para_a_proxima releitura=#{releitura} #{e.message}")
  end

  # As tentativas da chegada acabaram. A varredura só relê mensagem do cliente; a da equipe ela não relê.
  def avisar_desistencia(erro)
    mensagem = Message.find_by(id: arguments.first)
    destino = if mensagem.nil?
                'falha_passageira_sem_varredura mensagem_apagada'
              elsif mensagem.incoming?
                'falha_passageira_fica_para_a_varredura'
              else
                'falha_passageira_sem_varredura mensagem_de_saida'
              end
    Rails.logger.warn("[crm][midia] #{destino} #{erro.message} job=#{job_id}")
  end
end
