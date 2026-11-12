# O PEDIDO DO EXPERIMENTE PREMIUM (#2858, F7, revisor 12/11). A consulta paga não cabe no corte do pedido web (15 s): os
# prazos da BigDataCorp vão de 20 a 120 s (`Premium::Dataset`). O clique abre um pedido aqui, o `ExperimentePagoJob`
# roda a consulta em segundo plano, e a tela pergunta pelo id (`GET experimentar/:pedido`) até o resultado.
#
# O estado fica no Redis, com prazo (`TTL`), numa chave por pedido. O id é aleatório e o pedido é preso à conta: a
# leitura de outra conta não acha nada (404). A tela nunca recebe a conta, a fonte, o texto digitado nem a escolha do
# preço; o texto digitado só fica até o job ler, e sai do estado quando o resultado chega. Uma passada só por pedido
# (`reivindicar`): o job que o Sidekiq devolve à fila depois de começar não consulta de novo.
module Autonomia::FerramentasProntas::Experimente::Pedido
  TTL = 15.minutes
  # Quanto o job pode demorar a começar depois do clique (a espera na fila `agent_tools`). Folga de desenho, não medida: o
  # mesmo valor de antes do #2946 (80 - 12 - 57 - 2 = 9 s). O job que começa depois dele não consulta
  # (`ExperimentePagoJob`): a tela já teria desistido, e a consulta seria feita e cobrada sem ninguém ver.
  PRAZO_PARA_COMECAR = 9.seconds
  # Gravar o resultado e a tela perguntar por ele. Folga de desenho, não medida.
  FOLGA_DA_GRAVACAO = 2.seconds
  # Quanto a tela espera pelo resultado. Vai à tela na resposta do clique (`prazo_ms`); depois dele, ela desiste. Sai da
  # soma do caminho inteiro, com a consulta Premium mais lenta do catálogo (`Premium.prazo_maximo`, #2946):
  #   - começar (`PRAZO_PARA_COMECAR`);
  #   - antes da consulta, as idas ao modelo e as recusas: o `ComModelo` não começa consulta depois de
  #     `PRAZO_DAS_CONSULTAS`, quantas rodadas tenham passado;
  #   - a consulta (`Premium.prazo_maximo`);
  #   - depois dela, uma ida ao modelo só: passado o `MAX_SEGUNDOS`, o laço não abre rodada nova e fecha com a ida final
  #     (`ResponsesClient#create_with_tool_executor`);
  #   - a gravação.
  # Hoje 9 + 8 + 122 + 6 + 2 = 147 s.
  PRAZO_DA_TELA = PRAZO_PARA_COMECAR +
                  Autonomia::FerramentasProntas::Experimente::ComModelo::PRAZO_DAS_CONSULTAS.seconds +
                  Autonomia::FerramentasProntas::Premium.prazo_maximo.seconds +
                  Autonomia::FerramentasProntas::Experimente::ComModelo::PRAZO_DO_MODELO.seconds + FOLGA_DA_GRAVACAO
  CONSULTANDO = 'consultando'.freeze
  PREFIXO = 'ferramentas_prontas:experimente:'.freeze
  # Um id que passa disso não é nosso: nem é procurado.
  MAX_ID = 64
  SO_DO_SERVIDOR = %w[conta fonte valor confirmou_preco aberto_em].freeze

  module_function

  # -> o id do pedido. `aberto_em` (segundos desde a época): o job confere se ainda cabe no prazo da tela.
  def abrir!(account:, fonte:, valor:, confirmou_preco:)
    id = SecureRandom.uuid
    gravar(id, 'conta' => account.id, 'fonte' => fonte, 'valor' => valor, 'confirmou_preco' => confirmou_preco,
               'situacao' => CONSULTANDO, 'aberto_em' => Time.current.to_f)
    id
  end

  # -> o estado inteiro (para o job), ou nil.
  def ler(id)
    return if id.to_s.empty? || id.to_s.length > MAX_ID

    texto = Redis::Alfred.get(chave(id))
    texto.present? ? JSON.parse(texto) : nil
  end

  # A primeira passada do job ganha; as outras não consultam. -> true para quem ganhou.
  def reivindicar(id)
    Redis::Alfred.set("#{chave(id)}:job", '1', nx: true, ex: TTL.to_i) ? true : false
  end

  # O resultado, no lugar do pedido: o texto digitado e a escolha do preço saem.
  def concluir!(id, conta_id, resultado)
    gravar(id, resultado.merge('conta' => conta_id))
  end

  # -> o que a tela vê ({ situacao, dados?, mais_provavel?, premium? }), ou nil se o pedido não existe ou é de outra
  # conta.
  def para_tela(id, account:)
    pedido = ler(id)
    return if pedido.nil? || pedido['conta'] != account.id

    pedido.except(*SO_DO_SERVIDOR)
  end

  def gravar(id, estado)
    Redis::Alfred.setex(chave(id), estado.to_json, TTL.to_i)
  end

  def chave(id)
    "#{PREFIXO}#{id}"
  end
end
