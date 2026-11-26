# As FALHAS DA UNIVERSAL nas ferramentas do Seguro Viagem (#3211): o tratamento único que a cotação e a proposta chamam
# quando o cliente HTTP da seguradora levanta `Universal::Cliente::Erro` (ou a compra volta sem link).
#
# Cada falha faz as mesmas quatro coisas: atualiza o acesso do agente quando o erro é do acesso, deixa uma nota PRIVADA
# para a equipe (uma por conversa e ação, pela chave da nota), registra a recusa em `Tools::Recusa` (R5: nenhuma
# recusa fica sem registro) e devolve ao modelo o texto que ele deve seguir. Não é incluído nas ferramentas: elas
# chamam `Falhas.tratar`, e tudo chega por argumento.
#
# NUNCA LEVANTA. A nota (`NotaNaHora`) e o registro (`Recusa`) já não levantam; a gravação do acesso fica num
# `rescue`. A mensagem curta da seguradora (`pedido_invalido`) vai só ao modelo: nunca a log nem à nota. O texto ao
# modelo não traz status HTTP, login nem senha.
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

  module_function

  # -> o texto que o modelo lê. `acao` é o slug da ferramenta que chamou.
  def tratar(erro, acao:, agent:, conversation:)
    case erro.codigo
    when Codigos::ACESSO_RECUSADO then recusado(acao, agent, conversation)
    when Codigos::PEDIDO_INVALIDO then invalido(erro, acao, agent, conversation)
    else indisponivel(acao, agent, conversation)
    end
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

  private_class_method :recusado, :indisponivel, :invalido, :marcar_recusado, :nota
end
