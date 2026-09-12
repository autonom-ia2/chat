# O QUE A PROPOSTA ENTREGA — E O QUE ELA AFIRMA — QUANDO A EXECUÇÃO ACABA SEM FECHAR (entrega 8,
# rodadas 3 a 6).
#
# Quatro respostas ao `Tools::Encerramento`, que é o único caminho que sobra quando o prazo estoura
# ou a corrente de jobs se rompe: o que ainda vale entregar, o que disso virou mensagem agora, se o
# cliente já tem RESULTADO em mãos e se SOBROU alguma coisa. As duas últimas decidem entre a frase
# parcial e o silêncio — e é por elas que o cliente que pediu UMA proposta e recebeu essa uma parou
# de ler "não consegui enviar todas as propostas a tempo" (rodada 6, P1-B).
#
# AS CHAVES DO HANDLE VÊM PELA CLASSE (`self.class::PENDENTES`), e não pelo nome curto: elas moram
# em `Geracao`, e dentro de um módulo compacto o nome curto não se resolve — o mesmo cuidado de
# `Publicacao` e de `Comparativo` (C7 da auditoria).
#
# Separado da ferramenta pelo mesmo motivo dos outros módulos dela: é outro assunto, e a classe está
# no teto de linhas.
module Autonomia::Agents::Tools::Native::InsuranceProposal::Fecho
  extend ActiveSupport::Concern

  # O QUE AINDA VALE ENTREGAR QUANDO A EXECUÇÃO ACABA SEM FECHAR (o prazo estourou, o job desistiu),
  # no mesmo molde do comparativo da cotação: a proposta que o portal GEROU e não chegou ao cliente,
  # mais o aviso de quem ficou pelo caminho — quem estava só PENDENTE no fim é, para quem espera, o
  # mesmo que não gerada. Origem morta, substituída ou ausente: nada, porque o arquivo é dos preços
  # que o cliente descartou.
  #
  # UM ARQUIVO SÓ, também aqui (rodada 4, menor 1 do verificador cego): dois downloads de 20 s na
  # mesma passada passam dos 25 s que o Sidekiq dá ao job num shutdown, e quem é morto no meio perde
  # o segundo PARA SEMPRE — a marca `closed` já foi adquirida, e ninguém volta a este caminho. O
  # segundo arquivo fica no handle e o cliente lê o fecho parcial, que é honesto sobre isso.
  #
  # E ANOTA O QUE JÁ VIROU MENSAGEM antes de sair (rodada 4, importante 1 do verificador cego):
  # `confirmar` só rodava no `poll`, então uma proposta entregue na última passada antes do prazo
  # sumia da medida da entrega 7 — o cliente com o PDF no WhatsApp e a cotação sem marca nenhuma.
  #
  # `trabalho_novo` NÃO MUDA NADA AQUI (rodada 6, P2-E), e é por isso que ele não aparece no corpo:
  # este caminho não chama o portal. A URL da proposta já está no handle — o portal a gerou numa
  # passada anterior —, e o download é do publicador. Pelo varredor sai igual: o que ficou pronto e
  # não chegou ao cliente é justamente o que não pode morrer no handle.
  def closing_deliveries(handle, trabalho_novo: true) # rubocop:disable Lint/UnusedMethodArgument
    handle = handle.to_h
    return [] unless origem_ainda_vale?

    confirmar(handle)
    faltam = nao_publicadas(handle)
    faltam.first(1).map { |proposta| entrega(proposta, handle['sufixo']) } +
      aviso_da_gerada(faltam.drop(1)) +
      aviso_de(handle[self.class::NAO_SAIU].to_h.keys + Array(handle[self.class::PENDENTES]))
  end

  # O QUE VIROU MENSAGEM AGORA, no próprio encerramento (rodada 5; resíduo aberto na rodada 4).
  # `closing_deliveries` monta o que falta ANTES de a mensagem existir, e quem publica é o
  # `Tools::Encerramento`, logo depois — sem esta chamada, a proposta entregue no fecho ficava fora da
  # medida da entrega 7: o cliente com o PDF no WhatsApp e a cotação sem marca nenhuma.
  #
  # Anotar aqui NÃO é faturar o que o cliente não recebeu (o defeito 3 da rodada 3): a pergunta
  # continua sendo a MENSAGEM publicada, nunca o handle — a publicação que voltou `blocked` não
  # deixou mensagem, e não é anotada. Fica de fora só a ADIADA, que vira mensagem depois de todo
  # mundo ter ido embora.
  def confirmar_publicadas(handle)
    return unless origem_ainda_vale?

    confirmar(handle.to_h)
    nil
  end

  # O CLIENTE JÁ TEM UMA PROPOSTA NA MÃO? (rodada 6, P1-B.) A pergunta é a MESMA de sempre — existe a
  # MENSAGEM com o token desta proposta? —, nunca o handle: a publicação que voltou `blocked` não
  # deixou mensagem, e a ADIADA vira mensagem ~90 s depois, quando já não há ninguém para contá-la.
  # Nos dois casos a resposta é "ainda não", que é o lado conservador: o fecho cala em vez de afirmar.
  def resultado_entregue?(handle)
    handle = handle.to_h
    geradas(handle).any? { |proposta| publicada?(proposta, handle['sufixo']) }
  end

  # SOBROU PROPOSTA POR ENTREGAR? (rodada 6, P1-B.) Perguntado DEPOIS das entregas do encerramento, e
  # é o que separa o cliente que pediu UMA e recebeu essa uma — nada sobrou, e "não consegui enviar
  # todas as propostas a tempo" seria falso — de quem ficou sem a segunda: a gerada que não coube na
  # passada, a que o portal não gerou, a que nem chegou a ser pedida.
  #
  # Com a origem já não valendo, nada mais vai sair por este caminho e o cliente já leu o porquê (a
  # recusa nomeada): sobra nenhuma, e o fecho não repete o assunto com outra explicação.
  def resta_entregar?(handle)
    handle = handle.to_h
    return false unless origem_ainda_vale?

    nao_publicadas(handle).any? || Array(handle[self.class::PENDENTES]).any? || handle[self.class::NAO_SAIU].to_h.any?
  end

  private

  # A QUE O PORTAL GEROU E NÃO COUBE NESTA PASSADA (rodada 5, P3 do revisor final). O encerramento
  # entrega UM arquivo, e a segunda gerada é descartada — trade-off medido (25 s de shutdown), e ele
  # fica. O que não fica é o cliente lendo "não consegui gerar todas" sobre um arquivo que EXISTE:
  # ela é dita pelo nome, com o que fazer. Nunca entra em `aviso_de`, que é de quem NÃO foi gerada.
  def aviso_da_gerada(propostas)
    nomes = nomes_de(propostas.map { |proposta| proposta['code'].to_s })
    nomes.any? ? [nao_enviada(nomes)] : []
  end
end
