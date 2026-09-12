# A ENTREGA QUE O PUBLICADOR ACEITOU — o registro do ACEITE, gravado na hora dele (entrega 8a).
#
# QUEM PERGUNTA "O CLIENTE RECEBEU?" PERGUNTA AQUI. Havia dois candidatos antes deste, e os dois
# respondiam a outra pergunta:
#
#   - o HANDLE da ferramenta é a INTENÇÃO de quem publicou: `deliver` roda antes de
#     `record_attempt!`, então uma entrega RECUSADA (`blocked`) avança o handle sem que mensagem
#     nenhuma tenha entrado. Foi o defeito da rodada 1: "os preços acima são os que chegaram" sem
#     nada acima;
#   - a MENSAGEM na conversa é o fato, mas ela não existe ainda quando a publicação é ADIADA — e o
#     adiamento é NORMAL, não avaria: enquanto a cadeia de entrega humanizada do turno está em
#     curso (até 90 s), toda entrega volta `deferred` e sai sozinha pelo `AsyncPublishJob`. Foi o
#     defeito da rodada 3: nessa janela o fecho lia "nenhum preço chegou", não pedia o comparativo
#     e não dizia uma palavra — o cliente recebia os preços pelo job adiado e mais nada.
#
# O ACEITE É O QUE ESTÁ ENTRE OS DOIS, e é o estado que o publicador de fato conhece: ele assumiu
# esta entrega, imediata (`published`) ou adiada (`deferred`). Recusa (`blocked`) não grava nada, e
# é por isso que o defeito da rodada 1 não volta.
#
# A LISTA MORA NO HANDLE DA EXECUÇÃO e é uma MARCA do motor (`AsyncRunJob::MARCAS`): a ferramenta
# não a vê no handle que recebe e não a reescreve por cima quando devolve o seu — ela pergunta pela
# LINHA (`run`), que é o que ela já recebe para montar a identidade de cada entrega.
#
# QUEM REGISTRA É QUEM PUBLICA: o motor (`AsyncRunJob#deliver`) e o encerramento
# (`Tools::Encerramento#publicar_uma`). O aviso de espera e as frases de fecho NÃO passam por aqui
# — elas não são entrega da ferramenta, e o fecho idempotente continua perguntando pela mensagem
# (ver `Tools::EntregaPublicada`).
module Autonomia::Agents::Tools::EntregaAceita
  CHAVE = ::Autonomia::Agents::ToolRun::ENTREGAS_ACEITAS

  module_function

  # Grava o token quando a publicação foi aceita. -> o próprio resultado, para quem chamou decidir.
  #
  # Sem execução ou sem `execution_key` não há token, e aí não se grava nada: quem não tem
  # identidade não afirma nada depois. A falha da ESCRITA não pode derrubar a entrega que já está
  # no ar — ela vira log, e o fecho decide pelo lado conservador (como se não tivesse sido aceita).
  #
  # MAS ELA NÃO É A ÚLTIMA PALAVRA QUANDO QUEM CHAMA AINDA VAI PERSISTIR (rodada 6): o token fica
  # pendente em memória, no objeto da linha, e o `record_attempt!` do fim da passada o reescreve.
  # Sem isso, uma falha transitória do banco — sem morte de processo nenhuma — apagava o
  # encerramento: o fecho lia "nada aceito", calava, e a `main` teria falado pelo contador. É a rede
  # que a identidade da entrega sempre teve, e que faltava deste lado.
  #
  # A REDE É DO CHAMADOR, E SÓ UM DOS DOIS A TEM (precisão da rodada 7): `AsyncRunJob#deliver`
  # termina em `record_attempt!` e ganha a segunda escrita; `Tools::Encerramento#publicar_uma` não
  # — no motor o encerramento roda em `fail_run`, depois da última persistência, e no varredor não
  # há `record_attempt!` nenhum. Ali vale UMA escrita, e o alcance é o declarado em R20.
  def registrar(run, entrega, resultado)
    return resultado unless resultado.respond_to?(:aceita?) && resultado.aceita?

    token = ::Autonomia::Agents::Tools::EntregaPublicada.token_de(run, entrega)
    run.registrar_entrega_aceita!(token) if token.present?
    resultado
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] registro do aceite falhou run=#{run&.id} #{e.class}")
    resultado
  end

  # Esta identidade está na lista do aceite DESTA execução?
  def aceita?(run, token)
    return false if run.blank? || token.blank?

    Array(run.handle.to_h[CHAVE]).map(&:to_s).include?(token.to_s)
  end
end
