# "O que aconteceu" numa automação (#2498, F5 do #2414): as execuções mais recentes, 20 por página, com os passos de
# cada uma em ordem. Devolve só ids, chaves e horas, nunca texto da conversa (D8). A frase do passo sai na tela, da
# receita da versão em que a execução entrou; o motivo sai daqui, já traduzido.
#
# Visibilidade: a execução numa conversa que quem vê não enxerga aparece sem nome, sem link e sem ids de mensagem. O
# filtro é o da lista de conversas (`Conversations::PermissionFilterService`, só leitura). Alvo que não é conversa
# (card, contato) fica oculto até o `Autonomia::Automacao::Contexto` da F3 (#2499), que nomeia cada tipo.
class Autonomia::Automacao::Historico
  POR_PAGINA = 20
  SEMANA = 7.days
  # O que a lista chama de "parou": terminou sem chegar ao fim (parada, falhou ou interrompida).
  PAROU = %w[parada falhou interrompida].freeze
  # As chaves de `dados` que a tela sabe dizer. Chave fora da lista não sai: o passo novo (os `campos` da F7, por
  # exemplo) declara a dele e a frase no próprio PR.
  # `conversa_principal_do_card` (#2680): a mensagem abriu a conversa e ela virou a principal do card.
  # `sem_prazo` (#2750): o "esperar até" sem prazo, que só termina pela condição. `conferir_as` (G64): a hora da
  # conferência dele. `vez` e `volta` (G63): a vez do galho "a cada mensagem" e a volta dele à espera. O marco das
  # mensagens não sai: são ids de mensagem.
  # `numero_novo` (G43, #2700): a mensagem saiu no número novo do contato, em outra conversa da mesma caixa.
  CHAVES = %w[ramo ate sem_prazo conferir_as vez volta tentativa ia conversa_principal_do_card conversas_fora numero_novo].freeze
  # Estas apontam para dentro da conversa: só saem para quem a enxerga.
  CHAVES_DA_CONVERSA = %w[mensagem_id nota_id conversa_aberta].freeze
  # Dentro de `ia`, só os números do custo: a razão da IA ou um trecho lido seriam texto da conversa.
  IA = %w[custo_usd modelo tokens_entrada tokens_saida].freeze
  # O valor em dinheiro é custo da conta: só sai com `com_valores` (administrador ou financial_view, #1969, #2557). Os
  # tokens contam como dinheiro: com o preço público, dão o valor.
  DINHEIRO = %w[custo_usd tokens_entrada tokens_saida].freeze
  # A tela promete "nos últimos 30 dias": é o tempo em que os passos (Registro) ficam.
  JANELA = ::Autonomia::Automacao::Registro::RETENCAO
  # O tipo do alvo como a tela o chama. Tipo novo, até o Contexto da F3, sai pelo nome da classe.
  TIPOS = { 'Conversation' => 'conversa' }.freeze

  # As contagens da lista, numa consulta agrupada só: { automacao_id => { rodou:, parou: } } nos últimos 7 dias. Conta
  # todas as execuções, também as de conversas que quem vê não enxerga, porque o número não diz de quem foi.
  def self.semana(automacao_ids)
    recentes = ::Autonomia::Automacao::Execucao.where(automacao_id: automacao_ids, created_at: SEMANA.ago..)
    contagens = recentes.group(:automacao_id, :estado).count
    contagens.each_with_object(Hash.new { |hash, id| hash[id] = { rodou: 0, parou: 0 } }) do |((id, estado), total), semana|
      semana[id][:rodou] += total
      semana[id][:parou] += total if PAROU.include?(estado)
    end
  end

  def initialize(automacao:, usuario:, com_valores: false, pagina: 1)
    @automacao = automacao
    @usuario = usuario
    @ia = com_valores ? IA : IA - DINHEIRO
    @pagina = [pagina.to_i, 1].max
  end

  def resultado
    recentes = @automacao.execucoes.where(created_at: JANELA.ago..).order(created_at: :desc, id: :desc)
    lidas = recentes.offset((@pagina - 1) * POR_PAGINA).limit(POR_PAGINA + 1).to_a
    execucoes = lidas.first(POR_PAGINA)
    registros = registros_de(execucoes)
    visiveis = conversas_visiveis(execucoes)
    {
      execucoes: execucoes.map { |execucao| para_tela(execucao, registros.fetch(execucao.id, []), visiveis) },
      versoes: versoes_de(execucoes),
      pagina: @pagina,
      mais: lidas.size > POR_PAGINA
    }
  end

  private

  def registros_de(execucoes)
    ::Autonomia::Automacao::Registro.where(execucao_id: execucoes.map(&:id)).order(:created_at, :id).group_by(&:execucao_id)
  end

  # As receitas da página de uma vez, por versão única (várias execuções costumam estar na mesma versão).
  def versoes_de(execucoes)
    ::Autonomia::Automacao::Versao.where(id: execucoes.map(&:versao_id).uniq)
                                  .to_h { |versao| [versao.id, { numero: versao.numero, receita: versao.receita_para_tela }] }
  end

  # { conversation_id => conversa } das que quem vê enxerga, com o contato, numa consulta só.
  def conversas_visiveis(execucoes)
    ids = execucoes.select { |execucao| execucao.alvo_type == 'Conversation' }.map(&:alvo_id)
    return {} if ids.empty?

    conversas = Conversation.where(account_id: @automacao.account_id, id: ids)
    Conversations::PermissionFilterService.new(conversas, @usuario, @automacao.account, for_reading: true)
                                          .perform.includes(:contact).index_by(&:id)
  end

  def para_tela(execucao, registros, visiveis)
    conversa = visiveis[execucao.alvo_id] if execucao.alvo_type == 'Conversation'
    {
      id: execucao.id, estado: execucao.estado, versao_id: execucao.versao_id, criada_em: execucao.created_at,
      finalizada_em: execucao.finalizada_em, **espera(execucao, registros),
      alvo: alvo(execucao, conversa),
      passos: registros.map { |registro| passo(registro, visivel: conversa.present?) }
    }
  end

  # Até quando espera. Sem prazo (#2750), o `due_at` é só a próxima conferência do motor, não uma hora para mostrar: sai
  # `esperando_sem_prazo`. O registro da espera diz qual é (o da execução aberta não sai pela limpeza).
  def espera(execucao, registros)
    return { esperando_ate: nil } unless execucao.estado == 'esperando'
    return { esperando_ate: nil, esperando_sem_prazo: true } if registros.any? { |r| r.passo == execucao.cursor && r.dados['sem_prazo'] }

    { esperando_ate: execucao.due_at }
  end

  def alvo(execucao, conversa)
    return { tipo: TIPOS.fetch(execucao.alvo_type) { execucao.alvo_type.underscore }, visivel: false } if conversa.nil?

    { tipo: 'conversa', visivel: true, conversa_id: conversa.display_id, nome: conversa.contact&.name }
  end

  # `conversas_fora` (G42) sai só como quantidade: os ids são de conversas que quem vê pode não enxergar.
  def dados_para_tela(dados, chaves)
    lidos = dados.slice(*chaves)
    lidos['conversas_fora'] = Array(lidos['conversas_fora']).size if lidos.key?('conversas_fora')
    ia = lidos.delete('ia')
    ia.is_a?(Hash) ? lidos.merge('ia' => ia.slice(*@ia)) : lidos
  end

  # Os números do registro para o texto do motivo (G55: quantos chegaram e quantos ficaram de fora da campanha da vez) e,
  # em `por`, o texto de outro motivo (a campanha da vez que não saiu diz por quê).
  def contagens(dados)
    numeros = dados.select { |_, valor| valor.is_a?(Integer) }.transform_keys(&:to_sym).except(*I18n::RESERVED_KEYS)
    por = dados['por']
    por.is_a?(String) ? numeros.merge(por: I18n.t("autonomia.automacao.motivos.#{por}", default: '')) : numeros
  end

  def passo(registro, visivel:)
    chaves = visivel ? CHAVES + CHAVES_DA_CONVERSA : CHAVES
    {
      passo: registro.passo, resultado: registro.resultado, criado_em: registro.created_at,
      motivo: registro.motivo && I18n.t("autonomia.automacao.motivos.#{registro.motivo}", default: nil, **contagens(registro.dados)),
      dados: dados_para_tela(registro.dados, chaves)
    }
  end
end
