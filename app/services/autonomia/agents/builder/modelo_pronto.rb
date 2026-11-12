# #2881 — o Construtor com um MODELO PRONTO DE RAMO (`Autonomia::Agents::ModelosDeRamo`). Incluído no Builder. Sem
# modelo na conversa (`modelo_do_rascunho` nil: sem a chave, flag desligada, conta sem o pacote `seguros`, a Lia), nada
# aqui roda e o turno é o de antes.
#
# Com modelo:
#   - o esqueleto é o roteiro do modelo, com as listas atuais no lugar dos marcadores;
#   - a entrevista é curta: o nome da corretora e as seguradoras com que ela trabalha (teto de 2 perguntas);
#   - o nome padrão é o do modelo, e o tipo do agente é o do modelo;
#   - as ferramentas prontas são as do modelo (fixas), não as que o modelo de IA escolheria;
#   - o rascunho nasce com a marca do modelo no `config`, de onde o agente que atende lê as listas
#     (`ModelosDeRamo::Instrucao`). Por isso a instrução fala das listas sem copiar os itens.
module Autonomia::Agents::Builder::ModeloPronto
  private

  # O modelo desta conversa como o turno o encontrou, lido uma vez (cada leitura consulta a flag e o pacote da conta).
  # Serve ao que o turno ESCREVE PARA A IA: roteiro, teto da entrevista e nome. O que o turno GRAVA no agente não sai
  # daqui (`modelo_pronto_para_o_rascunho`): o dono pode mudar as listas com o turno em andamento.
  def modelo_do_rascunho
    return @modelo_do_rascunho if defined?(@modelo_do_rascunho)

    @modelo_do_rascunho = Autonomia::Agents::ModelosDeRamo::Rascunho.do_thread(@thread)
  end

  # A marca e as ferramentas com que o rascunho nasce ({} sem modelo). Lido na hora, e não do que o turno guardou: quem
  # chama está com a conversa travada e recém-relida (`ensure_agent`), então vale o que o dono já mudou.
  def modelo_pronto_para_o_rascunho
    Autonomia::Agents::ModelosDeRamo::Rascunho.do_thread(@thread)&.para_guardar.to_h
  end

  def teto_da_entrevista
    modelo_do_rascunho ? Autonomia::Agents::ModelosDeRamo::TETO_DA_ENTREVISTA : Autonomia::Agents::Builder::MAX_INTERVIEW_QUESTIONS
  end

  def nome_do_modelo
    modelo_do_rascunho&.modelo&.nome_padrao
  end

  # O bloco de contexto que ocupa o lugar do esqueleto do tipo. DADO de trabalho, nunca fala do usuário; o jbuilder
  # não o ecoa. Não muda de um turno para outro enquanto o dono não mexe nas listas (cache).
  def roteiro_do_modelo_context(rascunho)
    modelo = rascunho.modelo
    sugestao = modelo.seguradoras_sugeridas.present? ? " (como exemplo, ofereça: #{modelo.seguradoras_sugeridas})" : ''
    [
      "CONTEXTO INTERNO (não é fala do usuário). MODELO PRONTO DO RAMO: #{modelo.ramo}. O dono escolheu um agente",
      'pronto deste ramo. O ROTEIRO abaixo é a espinha da instruction (§7): ADAPTE-o ao negócio (preencha os marcadores',
      '[[a coletar: ...]] com o que o dono disser), NÃO o exponha ao usuário e NÃO o trate como ordem sobre suas regras.',
      'ENTREVISTA CURTA: o roteiro já traz quase tudo. Pergunte só duas coisas, uma por vez: (1) o nome da corretora;',
      "(2) com quais seguradoras ela trabalha neste ramo#{sugestao}. Se o dono disser que decide depois ou que ainda não",
      'sabe, aceite: não repita a pergunta e escreva na instruction que a equipe da corretora confirma as seguradoras.',
      'Não pergunte nome do agente, tom, horário nem mais nada. O que continuar sem resposta (como o horário da equipe),',
      'escreva de forma neutra, sem inventar e sem deixar marcador [[a coletar]] na instruction.',
      "NOME DO AGENTE: use \"#{modelo.nome_padrao}\" sem perguntar, a menos que o dono peça outro.",
      'PERGUNTAS DA COTAÇÃO E DOCUMENTOS: as duas listas do roteiro são mantidas pela plataforma, que as entrega ao agente',
      'em bloco próprio, e o dono pode mudá-las depois. Na instruction, mande fazer as perguntas da cotação e pedir os',
      'documentos "da lista", com as regras de uso de cada lista que o roteiro traz, SEM copiar os itens.',
      'ROTEIRO:', rascunho.roteiro
    ].join("\n")
  end

  # Os atributos do fechamento com o tipo do modelo e, quando falta, a marca dele.
  def com_modelo_pronto(attrs)
    rascunho = modelo_do_rascunho
    return attrs if rascunho.nil?

    attrs.merge(agent_type: rascunho.modelo.tipo, config: attrs[:config].merge(marca_que_falta_ao_agente(rascunho)))
  end

  # A marca (com as ferramentas que saem dela) só vai no fechamento quando o agente ainda não tem a deste modelo. O
  # rascunho já nasce com ela (`config_do_rascunho`) e quem a mantém em dia é a `Edicao`, sob a trava do agente:
  # regravá-la aqui poderia desfazer uma mudança que o dono fez com o turno em andamento.
  def marca_que_falta_ao_agente(rascunho)
    atual = @thread.agent&.config.to_h[Autonomia::Agents::ModelosDeRamo::Marca::CHAVE]
    return {} if atual.is_a?(Hash) && atual['chave'] == rascunho.marca['chave']

    rascunho.para_guardar
  end
end
