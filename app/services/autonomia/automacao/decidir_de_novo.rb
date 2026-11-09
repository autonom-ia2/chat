# Decidir a cada resposta (G31 do fechamento do #2414, exemplo 2, passo 6: "a cada resposta da Ana, a IA decide").
# O "decidir" com `de_novo` diz quais caminhos não seguem em frente: quando a IA escolhe um deles ("ainda
# conversando"), a execução volta a esperar a próxima resposta do cliente, até o prazo, e decide de novo.
#
# É uma opção do próprio "decidir", não um passo "voltar para": toda volta consome uma mensagem nova do cliente, então
# o laço acaba por construção e nunca gira pago sem resposta. Cada volta é uma ida paga à IA.
#
# - A espera começa no instante da leitura (`@decidido_em`, gravado antes da ida à IA): a mensagem que chegou enquanto
#   a IA pensava (rajada) faz decidir de novo na mesma rodada, sem esperar.
# - Ao retomar, a janela é do instante da leitura até o prazo (`due_at`). A resposta conta pela régua da G11
#   (Resposta.cliente?, só nas conversas que quem ligou vê). Acordada por outra coisa (a resposta da agente de IA, o
#   contato mudando), volta a esperar sem chamar a IA.
# - Vencido o prazo sem resposta, segue para o passo depois do "decidir", como um caminho sem passos (leitura literal
#   do termo): os passos de depois rodam sem a resposta; sem passo depois, a execução acaba.
# - A nova tentativa de um erro passageiro da IA roda direto, sem pedir outra resposta.
# Fica fora do Executor para ele seguir sendo a lista dos passos; usa os métodos dele (aguardar, registrar, contexto).
module Autonomia::Automacao::DecidirDeNovo
  NENHUM = ::Autonomia::Automacao::Receita::NENHUM

  # O passo é um "decidir" que pode voltar a esperar.
  def self.espera?(passo) = passo.is_a?(Hash) && passo['tipo'] == 'decidir' && passo['de_novo'].is_a?(Hash)

  # A IA escolheu um caminho que decide de novo.
  def self.repete?(passo, ramo) = espera?(passo) && Array(passo.dig('de_novo', 'caminhos')).include?(ramo)

  # O que o esquema não sabe dizer, conferido ao salvar: a chave é de um caminho do passo (ou "nenhum"), o caminho que
  # decide de novo não tem passos (sem "voltar para", eles nunca voltariam ao decidir) e sobra um caminho para seguir.
  def self.problemas_ao_salvar(passo)
    return [] unless espera?(passo)

    caminhos = Array(passo['caminhos'])
    marcados = Array(passo.dig('de_novo', 'caminhos'))
    [*desconhecidos(passo['id'], caminhos, marcados), *com_passos(passo, caminhos, marcados),
     *(caminhos.all? { |caminho| marcados.include?(caminho['chave']) } ? [texto(:de_novo_todos, passo: passo['id'])] : [])]
  end

  def self.desconhecidos(id, caminhos, marcados)
    (marcados - caminhos.pluck('chave') - [NENHUM]).map { |chave| texto(:de_novo_caminho_desconhecido, passo: id, chave: chave) }
  end

  def self.com_passos(passo, caminhos, marcados)
    cheios = caminhos.select { |caminho| marcados.include?(caminho['chave']) && Array(caminho['passos']).any? }.pluck('nome')
    cheios << texto(:caminho_nenhum) if marcados.include?(NENHUM) && Array(passo[NENHUM]).any?
    cheios.map { |nome| texto(:de_novo_com_passos, passo: passo['id'], nome: nome) }
  end

  # Os ramos do "decidir" no ensaio (Ensaio#decidir), um por caminho e o "nenhum": os passos que o bloco ensaia a partir
  # do primeiro. O caminho que decide de novo não tem passos (conferido ao salvar), então os dele são os de depois do
  # "decidir": é o que roda se o prazo vencer sem resposta. A marca `de_novo` faz a tela dizer que antes ele espera.
  def self.ramos_do_ensaio(passo, roteiro)
    caminhos = Array(passo['caminhos']).map { |item| [item['chave'], item['nome'], Array(item['passos']).first || roteiro.seguinte(passo['id'])] }
    [*caminhos, [NENHUM, nil, roteiro.entrar(passo, NENHUM)]].map do |chave, nome, primeiro|
      { chave: chave, nome: nome, de_novo: repete?(passo, chave) || nil, passos: yield(primeiro) }.compact
    end
  end

  def self.texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
  private_class_method :desconhecidos, :com_passos, :texto

  private

  # Depois de registrar o caminho (sem nota do motivo: "ainda conversando" deixaria uma por mensagem). A resposta que
  # chegou durante a ida à IA decide de novo já; senão, espera até o prazo, contado do instante da leitura.
  def esperar_resposta(passo)
    return passo if cliente_respondeu?(@decidido_em..)

    aguardar(passo, @decidido_em + prazo_de_novo(passo), registrar: false)
  end

  # O "decidir" com `de_novo` no cursor, ao retomar. O `due_at` é o da espera: a execução foi lida antes da troca.
  def retomar_decisao(passo)
    @retomando = false
    return passo_de_ia(passo, ::Autonomia::Automacao::PassoDeDecidir) if @tentativas.positive? || respondeu_na_espera?(passo)
    return aguardar(passo, @execucao.due_at, registrar: false) if @execucao.due_at&.future?

    registrar(passo['id'], 'pulado', 'prazo_vencido')
    @roteiro.seguinte(passo['id'])
  end

  def respondeu_na_espera?(passo) = cliente_respondeu?(::Autonomia::Automacao::Duracao.janela(passo.dig('de_novo', 'prazo'), @execucao.due_at))

  def cliente_respondeu?(janela) = ::Autonomia::Automacao::Resposta.cliente?(contexto.contato, janela, @definicao.ligada_por)

  def prazo_de_novo(passo) = ::Autonomia::Automacao::Duracao.de(passo.dig('de_novo', 'prazo'))
end
