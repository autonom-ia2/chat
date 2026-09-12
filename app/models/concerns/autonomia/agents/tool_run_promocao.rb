# QUANDO UMA ACEITAÇÃO VIRA TRABALHO (`pending` -> `running`), E QUANDO ELA JÁ NÃO PODE MAIS.
#
# A execução nasce `pending` dentro do turno e só o Responder a promove, no fim dele
# (`Tools::AsyncDispatcher`): se o turno morre — falha de IA na segunda chamada, sinal de silêncio,
# worker derrubado por um deploy —, ela é descartada e o portal nunca é chamado. Este módulo é essa
# fronteira, e ela tem DOIS lados que precisam concordar:
#
#   - a ESCRITA (`#promote!`): esta linha ainda pode virar trabalho?
#   - a LEITURA (`Native::InsuranceProposal::Origem`): esta linha ainda CONTA como uma cotação que o
#     cliente mandou refazer?
#
# Até a rodada 5 da entrega 8 só a leitura respeitava o teto de idade, e a discordância era a janela
# do P1-C: a aceitação de dez minutos não contava para quem lia e ainda assim era promovida — uma
# cotação aberta no portal por cima de uma conversa que seguiu sem ela.
#
# Extraído de `ToolRun` na rodada 6: o assunto é um só, e a classe está no teto de linhas.
module Autonomia::Agents::ToolRunPromocao
  extend ActiveSupport::Concern

  # ATÉ QUANDO UMA `pending` AINDA PODE VIRAR `running` (rodada 6 da entrega 8, P1-C). A promoção
  # acontece no fim do turno que aceitou; o turno tem teto de 120 s de HTTP
  # (`Crm::Ai::ResponsesClient#create_with_tool_executor`), e entre o aceite e a promoção ainda cabem
  # a segunda chamada ao modelo e o pós-processamento do respondedor — ancorar no teto de UMA chamada
  # era margem zero, no sentido inseguro. Cinco minutos é margem escolhida, não medida: o dano de
  # publicar a proposta de um risco que o cliente já corrigiu é maior que o de uma órfã segurar a
  # proposta por mais alguns minutos.
  PROMOCAO_ATE = 5.minutes

  # pending -> running. Guardado pelo status para que um despacho repetido (retry do turno) não
  # reabra uma execução que já terminou. -> true quando ESTA chamada promoveu.
  #
  # SOB O MESMO LOCK de `abrir_ou_repetida` (entrega 10): um turno B que leu a `pending` de A (que
  # não conta) não pode abrir enquanto A promove — ou A promove primeiro e B, ao entrar, encontra
  # uma `running` e não abre; ou B abre primeiro (supersede) e a promoção de A perde pelo status.
  # Sem isto, B supersedia uma execução já promovida e possivelmente submetida ao portal.
  #
  # E RECUSA A ACEITAÇÃO VELHA DEMAIS (rodada 6, P1-C): passada de `PROMOCAO_ATE`, esta linha é uma
  # órfã — o worker morreu entre o aceite e o despacho —, e quem a lê já não a conta como recotação.
  # Promovê-la abriria no portal uma cotação que o cliente pediu há muito tempo, por cima de uma
  # conversa que seguiu sem ela. Ela é DESCARTADA aqui mesmo, e não deixada em `pending`: uma linha
  # que ninguém vai executar e que ainda diz "aceita" engana quem a lê até o varredor passar, uma
  # hora depois.
  def promote!(expected_chunks:, notify_customer:, expires_at:)
    self.class.transaction do
      self.class.travar!(conversation_id, slug)
      next recusar_promocao_tardia! if promocao_tardia?

      guarded_update('pending', status: 'running', expected_chunks: expected_chunks.to_i,
                                notify_customer: notify_customer, expires_at: expires_at)
    end
  end

  # Descarta uma execução que nunca chegou a rodar (o turno morreu antes de despachar).
  def discard!
    guarded_update('pending', status: 'discarded')
  end

  private

  # Aceita há mais tempo do que o turno inteiro poderia levar para promovê-la (ver `PROMOCAO_ATE`).
  def promocao_tardia?
    status == 'pending' && created_at.present? && created_at < PROMOCAO_ATE.ago
  end

  # -> false, SEMPRE: esta chamada não promoveu. O descarte é o estado honesto da linha, não o
  # resultado da promoção.
  def recusar_promocao_tardia!
    Rails.logger.warn("[autonomia][tool][async] promocao recusada por idade run=#{id} slug=#{slug}")
    discard!
    false
  end
end
