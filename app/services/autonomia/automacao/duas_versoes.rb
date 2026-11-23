# #3099 (F3 do épico #3095): duas versões da mensagem no passo "mensagem" da Automação livre. Desenho em
# docs/3099-desenho/desenho.md (§2.2, §3 e §5.4).
#
# A receita guarda no passo `versoes: { texto, modelo, criterio, divisao, espera }` (esquema `duas_versoes`). A versão 1 é
# o próprio passo; a versão 2 troca o texto e, quando o passo usa modelo para a janela fechada, o modelo.
#
# - Cada execução sorteia a versão pelo hash de "automacao:passo:alvo" (#sorteio): o mesmo alvo cai sempre na mesma
#   versão. Com a vencedora escolhida, todo mundo recebe ela (DuasVersoes::Envio);
# - o teste fecha quando cada versão foi mandada MINIMO_POR_VERSAO vezes; depois da espera, o cron
#   (Autonomia::Automacao::EscolherVencedoraJob) escolhe a melhor pela régua da campanha (CampaignJourney::DuasVersoes::
#   Vencedora); empate ou poucas respostas, a versão 1. No "eu escolho", a vencedora espera alguém com automation_manage
#   (nada fica parado: até lá, cada pessoa continua recebendo uma das duas);
# - mudar o texto ou o modelo de uma das versões zera o teste (#versao_salva!, chamado por Definicao#salvar_versao!).
#
# Os números, o estado e a escolha moram em DuasVersoes::Teste e DuasVersoes::Numeros. As constantes são as da campanha
# (CampaignJourney::DuasVersoes), que a tela também usa (duasVersoes.js).
module Autonomia::Automacao::DuasVersoes
  REGRA = ::CampaignJourney::DuasVersoes
  VERSOES = REGRA::VERSOES
  MINIMO_POR_VERSAO = REGRA::MINIMO_POR_VERSAO
  # O que, mudando em uma das versões, zera o teste: o texto e o modelo.
  CONTEUDO = %w[texto modelo].freeze

  module_function

  def do_passo?(passo) = passo.is_a?(Hash) && passo['tipo'] == 'mensagem' && passo['versoes'].is_a?(Hash)

  # A classe que o executor usa para mandar o passo (Executor#passo_nativo): o "mensagem" com duas versões passa pelo
  # Envio, que escolhe a versão e chama o PassoDeMensagem de sempre.
  def classe_do(passo, classe) = do_passo?(passo) ? Envio : classe

  # O passo como sai na versão pedida, sem a chave `versoes`. A versão 2 troca o texto e, quando tem, o modelo.
  def passo_da_versao(passo, versao)
    base = passo.except('versoes')
    return base if versao == 1

    segunda = passo['versoes']
    base.merge('texto' => segunda['texto'], 'modelo' => segunda['modelo']).compact
  end

  # 1 ou 2, fixo para o alvo: a posição de 0 a 99 pelo hash, e a versão 1 fica com as primeiras `divisao` posições.
  def sorteio(automacao_id, passo, alvo)
    posicao = Digest::SHA256.hexdigest("#{automacao_id}:#{passo['id']}:#{alvo.class.polymorphic_name}:#{alvo.id}")[0, 8].to_i(16) % 100
    posicao < passo.dig('versoes', 'divisao').to_i.clamp(1, 99) ? 1 : 2
  end

  # A linha do teste do passo. Sem ela (o primeiro envio de um passo salvo antes da linha existir), o teste começa agora.
  def teste_de(automacao, passo_id)
    ::Autonomia::Automacao::VersaoVencedora.create_or_find_by!(automacao_id: automacao.id, passo: passo_id) do |linha|
      linha.account_id = automacao.account_id
      linha.teste_desde = Time.current
    end
  end

  # O passo com duas versões na versão ativa da automação; nil se ele não existe mais ou não testa mais duas versões.
  def passo_ativo(automacao, passo_id) = passos_com_versoes(automacao.versao_ativa&.receita)[passo_id]

  # { id do passo => passo } dos passos "mensagem" com duas versões da receita (inclusive dentro dos ramos).
  def passos_com_versoes(receita)
    return {} unless receita.is_a?(Hash)

    # Chaves em texto, como a receita gravada: a que chega do salvar pode vir com símbolos.
    passos = ::Autonomia::Automacao::Receita.new(JSON.parse(receita.to_json), conta: nil, account_user: nil).passos
    passos.select { |passo| do_passo?(passo) }.index_by { |passo| passo['id'] }
  end

  # Chamado ao salvar uma versão nova da automação (Definicao#salvar_versao!, dentro da trava dela). O passo que passou a
  # ter duas versões, ou cujo texto ou modelo mudou em uma delas, recomeça o teste: `teste_desde` agora e sem vencedora.
  # Mudar só a regra (critério, divisão, espera) não zera.
  def versao_salva!(automacao, anterior, nova)
    antes = passos_com_versoes(anterior)
    passos_com_versoes(nova).each do |id, passo|
      next if antes[id] && conteudo(antes[id]) == conteudo(passo)

      recomecar!(automacao, id)
    end
  end

  def conteudo(passo) = [passo.slice(*CONTEUDO), passo['versoes'].slice(*CONTEUDO)]

  def recomecar!(automacao, passo_id)
    linha = ::Autonomia::Automacao::VersaoVencedora.find_or_initialize_by(automacao_id: automacao.id, passo: passo_id)
    linha.update!(account_id: automacao.account_id, teste_desde: Time.current, vencedora: nil, escolhida_por: nil,
                  escolhida_por_user_id: nil, escolhida_em: nil)
  end

  # O resultado de cada passo com duas versões da versão ativa, para o histórico (GET automacoes/:id/duas_versoes). O
  # passo que ainda não mandou nada aparece com os números zerados (sem gravar a linha).
  def resultado(automacao, user:, account_user:)
    linhas = ::Autonomia::Automacao::VersaoVencedora.where(automacao_id: automacao.id).index_by(&:passo)
    passos_com_versoes(automacao.versao_ativa&.receita).map do |id, passo|
      linha = linhas[id] || ::Autonomia::Automacao::VersaoVencedora.new(automacao: automacao, account_id: automacao.account_id, passo: id,
                                                                         teste_desde: Time.current)
      Teste.new(linha, passo).payload(user: user, account_user: account_user)
    end
  end

  # As frases do que o esquema não sabe dizer (Receita::Mensagens): o modelo da versão 2 acompanha o da versão 1, as duas
  # versões não são iguais e "mais compras" pede o CRM. O texto e o modelo da versão 2 passam pela régua de sempre lá.
  def problemas_ao_salvar(passo)
    return [] unless do_passo?(passo)

    id = passo['id']
    segunda = passo['versoes']
    [(:versoes_sem_modelo if passo['modelo'] && segunda['modelo'].blank?),
     (:versoes_modelo_sobrando if segunda['modelo'].present? && passo['modelo'].blank?),
     (:versoes_iguais if passo_da_versao(passo, 1).slice(*CONTEUDO) == passo_da_versao(passo, 2).slice(*CONTEUDO)),
     (:versoes_sem_compras if segunda['criterio'] == 'compras' && !Crm::Config.enabled?)]
      .compact.map { |chave| I18n.t("autonomia.automacao.receita.#{chave}", passo: id) }
  end
end
