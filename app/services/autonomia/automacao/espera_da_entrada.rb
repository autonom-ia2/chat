# "Se nesse tempo não entrou de novo na etapa" (G50, exemplo 4, passo 10): o card do alvo entrou de novo na etapa do
# gatilho durante o "esperar até"? É o valor `card.entrou_de_novo`, que só vale na condição do "esperar até" e só no
# gatilho card.entrou_na_etapa (Valores.fora_do_lugar), onde a etapa é obrigatória.
#
# Lê o histórico do card (Crm::Activity "move" com `to_stage_id` = a etapa do gatilho da versão em que a execução
# entrou), dentro da janela da espera (Duracao.janela, a mesma da resposta, G11). Não usa `entered_stage_at`: o aluno
# pode entrar em "Faltou" e sair antes de a espera conferir, e o instante da etapa atual perde isso. A atividade de
# criação não entra: o card da espera já existia quando ela começou.
#
# O despertar: a nova entrada na etapa (Escuta.evento_do_card) reserva a execução do próprio card parada num "esperar
# até" que lê este valor, e ela confere agora, em vez de no fim do prazo. O filtro é o mesmo da reunião
# (EsperaDaReuniao.caminhos_da): a espera pela resposta do cliente no mesmo card não é reservada à toa.
module Autonomia::Automacao::EsperaDaEntrada
  VALOR = 'card.entrou_de_novo'.freeze
  GATILHO = 'card.entrou_na_etapa'.freeze
  VALORES = { VALOR => ->(contexto, espera, _quem) { entrou?(contexto.card, contexto.etapa_do_gatilho, espera) } }.freeze

  module_function

  # Sem card, sem etapa (a execução sem versão, o ensaio) ou sem janela, nunca entrou: "diferente de true" não vira
  # entrada.
  def entrou?(card, etapa_id, espera)
    return false if card.nil? || etapa_id.blank? || espera.nil?

    entradas = ::Crm::Activity.where(account_id: card.account_id, card_id: card.id, event_type: 'move')
                              .where("payload->>'to_stage_id' = ?", etapa_id.to_s)
                              .where('created_at > ?', espera.begin)
    (espera.end ? entradas.where('created_at <= ?', espera.end) : entradas).exists?
  end

  # O passo em que a execução espera lê `card.entrou_de_novo`?
  def le_entrada?(execucao)
    passo = ::Autonomia::Automacao::Roteiro.new(execucao.versao.receita).passo(execucao.cursor)
    ::Autonomia::Automacao::EsperaDaReuniao.caminhos_da(passo.to_h['condicao']).include?(VALOR)
  end

  # As execuções esperando no próprio card, presas à conta.
  def de(card) = ::Autonomia::Automacao::Execucao.where(account_id: card.account_id, estado: 'esperando', alvo: card)
end
