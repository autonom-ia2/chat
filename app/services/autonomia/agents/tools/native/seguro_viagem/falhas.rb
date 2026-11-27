# As FALHAS DA UNIVERSAL nas ferramentas do Seguro Viagem (#3211): o tratamento único que a cotação e a proposta chamam
# quando o cliente HTTP da seguradora levanta `Universal::Cliente::Erro` (ou a compra volta sem link).
#
# Cada falha faz as mesmas quatro coisas: atualiza o acesso do agente quando o erro é do acesso, deixa uma nota PRIVADA
# para a equipe (uma por conversa e ação, pela chave da nota), registra a recusa em `Tools::Recusa` (R5: nenhuma
# recusa fica sem registro) e devolve ao modelo o texto que ele deve seguir. Não é incluído nas ferramentas: elas
# chamam `Falhas.tratar`, e tudo chega por argumento.
#
# NUNCA LEVANTA. A nota (`NotaNaHora`) e o registro (`Recusa`) já não levantam; a gravação do acesso fica num
# `rescue`. A mensagem curta da seguradora (`pedido_invalido`, `compra_recusada`) vai só ao modelo: nunca a log nem à
# nota. O texto ao modelo não traz status HTTP, login nem senha.
#
# O 400 DA COMPRA (#3265, `tratar_compra`) é outro caso: o cliente já confirmou o resumo, então ele deixa nota à equipe
# e o texto não manda corrigir dado; o 400 das outras chamadas (cotar) segue no `tratar`.
module Autonomia::Agents::Tools::Native::SeguroViagem::Falhas
  Codigos = Autonomia::Seguradoras::Universal::Codigos
  NOTAS = 'autonomia.contratados.universal.notas'.freeze

  TEXTO_PASSAR = 'A seguradora recusou o acesso da corretora. Não tente de novo. Passe a conversa para a equipe agora e ' \
                 'diga ao cliente só que alguém da equipe vai continuar, sem falar do erro.'.freeze
  TEXTO_INDISPONIVEL = 'O sistema da seguradora não respondeu. Tente uma vez de novo; se falhar de novo, passe a ' \
                       'conversa para a equipe, sem mostrar o erro.'.freeze
  TEXTO_SEM_LINK = 'A seguradora não devolveu o link de pagamento. Não tente de novo. Passe a conversa para a equipe ' \
                   'agora, sem mostrar o erro.'.freeze
  TEXTO_INVALIDO = 'A seguradora não aceitou o pedido. Corrija com o cliente só o dado em questão.'.freeze
  # #3265: o 400 da COMPRA vem depois do resumo confirmado. Não é "corrija o dado" por padrão (ex.: "já consta um voucher
  # para essa viagem" não tem dado a corrigir): quem decide se a resposta da seguradora aponta um dado do cliente é o
  # modelo, pela instrução, nunca uma lista de palavras sobre o texto dela.
  TEXTO_COMPRA_RECUSADA = 'A seguradora recusou a compra, e a proposta não saiu. O cliente já confirmou o resumo: não ' \
                          'peça para ele corrigir dados e não tente de novo. Passe a conversa para a equipe agora, sem ' \
                          'mostrar o erro.'.freeze
  TEXTO_COMPRA_RECUSADA_COM_RESPOSTA = 'A seguradora recusou a compra, e a proposta não saiu. O cliente já confirmou o ' \
                                       'resumo, então não peça para ele revisar os dados. Só se a resposta da ' \
                                       'seguradora abaixo apontar claramente um dado que o cliente informou (o CPF ou a ' \
                                       'data de nascimento de um viajante, por exemplo), peça só esse dado, troque e ' \
                                       'confirme o resumo de novo; se a seguradora recusar de novo, passe a conversa ' \
                                       'para a equipe. Senão, não tente de novo: passe a conversa para a equipe agora, ' \
                                       'sem mostrar o erro.'.freeze

  module_function

  # -> o texto que o modelo lê. `acao` é o slug da ferramenta que chamou.
  def tratar(erro, acao:, agent:, conversation:)
    case erro.codigo
    when Codigos::ACESSO_RECUSADO then recusado(acao, agent, conversation)
    when Codigos::PEDIDO_INVALIDO then invalido(erro, acao, agent, conversation)
    else indisponivel(acao, agent, conversation)
    end
  end

  # A falha da COMPRA (#3265): o pedido inválido vira `compra_recusada`; as outras, como em `tratar`. `da_compra`:
  # `{ cotacao_id:, carrinhos: }`, a cotação da compra (a chave da nota) e os números dos carrinhos anteriores desta
  # conversa, que a nota cita (lista vazia sem nenhum).
  def tratar_compra(erro, da_compra:, acao:, agent:, conversation:)
    return tratar(erro, acao: acao, agent: agent, conversation: conversation) unless erro.codigo == Codigos::PEDIDO_INVALIDO

    cotacao_id, carrinhos = da_compra.values_at(:cotacao_id, :carrinhos)
    nota_da_compra_recusada(conversation, carrinhos, "#{acao}:#{conversation&.id}:#{cotacao_id}")
    compra_recusada(erro, acao, agent, conversation)
  end

  # A falha de uma consulta em que não há dado do cliente a corrigir (o pagamento pelo carrinho guardado, o catálogo de
  # coberturas): o pedido inválido é tratado como indisponível (#3246, #3249).
  def tratar_sem_dado_do_cliente(erro, acao:, agent:, conversation:)
    invalido = erro.codigo == Codigos::PEDIDO_INVALIDO
    tratado = invalido ? Autonomia::Seguradoras::Universal::Cliente::Erro.new(Codigos::INDISPONIVEL) : erro
    tratar(tratado, acao: acao, agent: agent, conversation: conversation)
  end

  # A compra voltou sem link de pagamento válido (`urlVoucher`).
  def sem_link(acao:, agent:, conversation:)
    nota(conversation, 'sem_link', acao)
    Autonomia::Agents::Tools::Recusa.registrar('sem_link', slug: acao, agente: agent, conversa: conversation&.id)
    TEXTO_SEM_LINK
  end

  def recusado(acao, agent, conversation)
    marcar_recusado(agent, conversation)
    nota(conversation, 'acesso_recusado', acao)
    Autonomia::Agents::Tools::Recusa.registrar('acesso_recusado', slug: acao, agente: agent, conversa: conversation&.id)
    TEXTO_PASSAR
  end

  def indisponivel(acao, agent, conversation)
    nota(conversation, 'indisponivel', acao)
    Autonomia::Agents::Tools::Recusa.registrar('indisponivel', slug: acao, agente: agent, conversa: conversation&.id)
    TEXTO_INDISPONIVEL
  end

  # A mensagem da seguradora vem de fora: vai rotulada como dado (`Recusa::AVISO_DE_DADO_EXTERNO`). Sem mensagem, só o
  # texto fixo.
  def invalido(erro, acao, agent, conversation)
    Autonomia::Agents::Tools::Recusa.registrar('pedido_invalido', slug: acao, agente: agent, conversa: conversation&.id)
    mensagem = erro.mensagem_da_seguradora.to_s.strip.presence
    return TEXTO_INVALIDO if mensagem.nil?

    "#{TEXTO_INVALIDO} Resposta da seguradora (#{Autonomia::Agents::Tools::Recusa::AVISO_DE_DADO_EXTERNO}): \"#{mensagem}\""
  end

  # A mensagem da seguradora vai só ao modelo, rotulada como dado externo, como no `invalido`; nunca à nota.
  def compra_recusada(erro, acao, agent, conversation)
    Autonomia::Agents::Tools::Recusa.registrar('compra_recusada', slug: acao, agente: agent, conversa: conversation&.id)
    mensagem = erro.mensagem_da_seguradora.to_s.strip.presence
    return TEXTO_COMPRA_RECUSADA if mensagem.nil?

    "#{TEXTO_COMPRA_RECUSADA_COM_RESPOSTA} Resposta da seguradora (#{Autonomia::Agents::Tools::Recusa::AVISO_DE_DADO_EXTERNO}): " \
      "\"#{mensagem}\""
  end

  # A nota leva só o número dos carrinhos anteriores (da Universal, não é dado pessoal), nunca o texto da seguradora.
  # Uma por cotação (`onde`: ação, conversa e cotação): a mesma recusa repetida na mesma cotação não duplica; a cotação
  # nova (o cliente cotou de novo) tem nota nova.
  def nota_da_compra_recusada(conversation, carrinhos, onde)
    texto = if carrinhos.empty?
              I18n.t("#{NOTAS}.compra_recusada")
            else
              I18n.t("#{NOTAS}.compra_recusada_com_anterior", carrinhos: carrinhos.join(', '))
            end
    Autonomia::Insurance::NotaNaHora.postar(conversation, texto, chave: "universal:compra_recusada:#{onde}")
  end

  # Como na conferência recusada (`ConferirAcesso`): o login recusado não guarda o que ele podia antes.
  def marcar_recusado(agent, conversation)
    agent.acesso_da_seguradora.update!(estado: 'recusado', motivo: Codigos::ACESSO_RECUSADO, capacidades: {})
  rescue StandardError => e
    Rails.logger.warn("[autonomia][seguro_viagem] acesso_nao_marcado agente=#{agent&.id} conv=#{conversation&.id} #{e.class}")
  end

  # Uma nota por conversa e ação: a assinatura não tem o turno, então a mesma falha na mesma conversa vira uma só.
  def nota(conversation, falha, acao)
    Autonomia::Insurance::NotaNaHora.postar(conversation, I18n.t("#{NOTAS}.#{falha}"),
                                            chave: "universal:#{falha}:#{acao}:#{conversation&.id}")
  end

  private_class_method :recusado, :indisponivel, :invalido, :compra_recusada, :nota_da_compra_recusada, :marcar_recusado, :nota
end
