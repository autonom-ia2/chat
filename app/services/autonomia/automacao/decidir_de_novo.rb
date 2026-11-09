# Decidir a cada resposta (G31 do fechamento do #2414, exemplo 2, passo 6: "a cada resposta da Ana, a IA decide").
# O "decidir" com `de_novo` diz quais caminhos não seguem em frente: quando a IA escolhe um deles ("ainda
# conversando"), a execução volta a esperar a próxima resposta do cliente, até o prazo, e decide de novo.
#
# É uma opção do próprio "decidir", não um passo "voltar para": toda volta consome uma mensagem nova do cliente, então
# o laço acaba por construção e nunca gira pago sem resposta. Cada volta é uma ida paga à IA.
#
# - O marco da leitura (Resposta.marco, gravado no registro do caminho) é o id da última mensagem do cliente visível
#   antes da ida à IA, o instante e as mensagens da margem de segundos antes dele. Nova é a de id maior (mesmo com
#   `created_at` de antes) ou a da margem que não estava visível (commit atrasado); a que a IA já leu nunca reconta. A
#   que chegou enquanto a IA pensava (rajada) faz decidir de novo na mesma rodada, sem esperar. O prazo conta do
#   instante da leitura (`@decidido_em`).
# - Ao retomar, conta a resposta depois do marco e até o prazo (`due_at`), pela régua da G11 (só nas conversas que
#   quem ligou vê). Acordada por outra coisa (a resposta da agente de IA, o contato mudando), volta a esperar sem
#   chamar a IA.
# - Vencido o prazo sem resposta, a execução acaba ('concluida') sem mandar nada, com o registro pulado 'prazo_vencido'
#   (decisão do Rodrigo, 09/11): os passos depois do "decidir" não rodam. É uma regra só, não configurável por caminho.
# - A nova tentativa de um erro passageiro da IA roda direto, sem pedir outra resposta.
# Fica fora do Executor para ele seguir sendo a lista dos passos; usa os métodos dele (aguardar, registrar, contexto).
module Autonomia::Automacao::DecidirDeNovo
  NENHUM = ::Autonomia::Automacao::Receita::NENHUM

  # O passo é um "decidir" que pode voltar a esperar.
  def self.espera?(passo) = passo.is_a?(Hash) && passo['tipo'] == 'decidir' && passo['de_novo'].is_a?(Hash)

  # A IA escolheu um caminho que decide de novo.
  def self.repete?(passo, ramo) = espera?(passo) && Array(passo.dig('de_novo', 'caminhos')).include?(ramo)

  # O que o esquema não sabe dizer, conferido ao salvar: a chave é de um caminho do passo (ou "nenhum"), o caminho que
  # decide de novo não tem passos (sem "voltar para", eles nunca voltariam ao decidir) e sobra uma saída para seguir:
  # um caminho ou o "nenhum", que é saída como os outros.
  def self.problemas_ao_salvar(passo)
    return [] unless espera?(passo)

    caminhos = Array(passo['caminhos'])
    marcados = Array(passo.dig('de_novo', 'caminhos'))
    [*desconhecidos(passo['id'], caminhos, marcados), *com_passos(passo, caminhos, marcados),
     *(todas_marcadas?(caminhos, marcados) ? [texto(:de_novo_todos, passo: passo['id'])] : [])]
  end

  def self.todas_marcadas?(caminhos, marcados) = [*caminhos.pluck('chave'), NENHUM].all? { |chave| marcados.include?(chave) }

  def self.desconhecidos(id, caminhos, marcados)
    (marcados - caminhos.pluck('chave') - [NENHUM]).map { |chave| texto(:de_novo_caminho_desconhecido, passo: id, chave: chave) }
  end

  def self.com_passos(passo, caminhos, marcados)
    cheios = caminhos.select { |caminho| marcados.include?(caminho['chave']) && Array(caminho['passos']).any? }.pluck('nome')
    cheios << texto(:caminho_nenhum) if marcados.include?(NENHUM) && Array(passo[NENHUM]).any?
    cheios.map { |nome| texto(:de_novo_com_passos, passo: passo['id'], nome: nome) }
  end

  # Os ramos do "decidir" no ensaio (Ensaio#decidir), um por caminho e o "nenhum": os passos que o bloco ensaia a partir
  # do primeiro. O caminho que decide de novo não roda passo nenhum: espera a próxima resposta e, vencido o prazo, a
  # execução acaba sem mandar nada. A marca `de_novo` faz a tela dizer isso.
  def self.ramos_do_ensaio(passo, roteiro)
    caminhos = Array(passo['caminhos']).map { |item| [item['chave'], item['nome'], Array(item['passos']).first || roteiro.seguinte(passo['id'])] }
    [*caminhos, [NENHUM, nil, roteiro.entrar(passo, NENHUM)]].map do |chave, nome, primeiro|
      de_novo = repete?(passo, chave)
      { chave: chave, nome: nome, de_novo: de_novo || nil, passos: de_novo ? [] : yield(primeiro) }.compact
    end
  end

  def self.texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
  private_class_method :todas_marcadas?, :desconhecidos, :com_passos, :texto

  private

  # Antes da ida à IA: o instante (o prazo conta dele) e o marco das mensagens do cliente. A mensagem gravada entre o
  # marco e a leitura da IA também decide de novo: paga uma volta, nunca some.
  def marcar_leitura(passo)
    return unless ::Autonomia::Automacao::DecidirDeNovo.espera?(passo)

    @decidido_em = Time.current
    @marco = ::Autonomia::Automacao::Resposta.marco(contexto.contato, @definicao.ligada_por, @decidido_em)
  end

  # Os dados do registro do caminho que decide de novo levam o marco: a espera confere a partir dele ao retomar.
  def dados_do_caminho(passo, dados)
    ::Autonomia::Automacao::DecidirDeNovo.repete?(passo, dados['ramo']) ? dados.merge(@marco) : dados
  end

  # Depois de registrar o caminho (sem nota do motivo: "ainda conversando" deixaria uma por mensagem). A resposta que
  # chegou durante a ida à IA decide de novo já; senão, espera até o prazo, contado do instante da leitura.
  def esperar_resposta(passo)
    return passo if cliente_respondeu?(@marco, nil)

    aguardar(passo, @decidido_em + prazo_de_novo(passo), registrar: false)
  end

  # O "decidir" com `de_novo` no cursor, ao retomar. O `due_at` é o da espera: a execução foi lida antes da troca.
  def retomar_decisao(passo)
    @retomando = false
    return passo_de_ia(passo, ::Autonomia::Automacao::PassoDeDecidir) if @tentativas.positive? || respondeu_na_espera?(passo)
    return aguardar(passo, @execucao.due_at, registrar: false) if @execucao.due_at&.future?

    encerrar(passo['id'], 'concluida', 'prazo_vencido')
  end

  def respondeu_na_espera?(passo) = cliente_respondeu?(marco_gravado(passo), @execucao.due_at)

  # O marco do último caminho registrado no passo (o que pôs a execução a esperar). Sem ele, quebra visível (fetch).
  def marco_gravado(passo)
    ::Autonomia::Automacao::Registro.where(execucao: @execucao, passo: passo['id']).order(:id).last.dados
  end

  # `ligada_por` não chega nil aqui: sem quem ligou, a rodada pausa antes com `sem_quem_ligou` (Executor#rodar e
  # IaNoExecutor#passo_de_ia, pelo impedida? → Acesso#motivo).
  def cliente_respondeu?(marco, ate)
    ::Autonomia::Automacao::Resposta.cliente_depois?(contexto.contato, marco, ate, @definicao.ligada_por)
  end

  def prazo_de_novo(passo) = ::Autonomia::Automacao::Duracao.de(passo.dig('de_novo', 'prazo'))
end
