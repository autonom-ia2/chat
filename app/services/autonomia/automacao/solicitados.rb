# G22 (#2414, exemplo 8, passo 9): "Toda sexta, para cada empresa com inclusão aberta, avisa o RH quem ainda não mandou
# documento." O RH é quem pediu os cards (crm_cards.solicitante_contact_id, que a criação dos cards do passo 3 grava).
# A condição `solicitante_de` do contato.recorrente (Tempo::Selecao) pega um RH por empresa, e o valor
# `contato.solicitados_faltando` (Valores) lista para ele quem ainda falta.
#
# - Pendente: card aberto do funil (e da etapa, quando escolhida), com solicitante, com algum dos campos `faltando`
#   (campos de marcar do card, que o passo 6 marca) ainda sem marcar. Tudo no SQL, as chaves como parâmetro.
# - Empresa: a do solicitante. Duas pessoas do RH da mesma empresa recebem um aviso só, quem fez o pedido pendente mais
#   novo, e a lista traz os pendentes da empresa inteira. O solicitante sem empresa responde só pelos pedidos dele.
# - Só os cards que a pessoa vê (`visiveis`, o escopo da política do card): quem ligou, na execução; quem pede, no
#   ensaio. Card de caixa que ela não vê nunca entra na seleção nem no texto.
class Autonomia::Automacao::Solicitados
  SEPARADOR = '; '.freeze
  JUNTA = 'INNER JOIN contacts solicitantes ON solicitantes.id = crm_cards.solicitante_contact_id'.freeze
  # A empresa do solicitante; sem empresa, ele mesmo.
  EMPRESA = 'solicitantes.company_id, (CASE WHEN solicitantes.company_id IS NULL THEN solicitantes.id END)'.freeze
  SEM_MARCAR = "(crm_cards.custom_attributes ->> ?) IS DISTINCT FROM 'true'".freeze
  # Os passos que gravam o solicitante no card que criam. Nenhum ainda: o "para cada item" do passo 3 (G24) é quem grava,
  # e põe o tipo dele aqui no mesmo commit em que passa a gravar. Sem gravador, card nenhum tem solicitante e o aviso de
  # sexta nunca sairia (pularia toda semana com `faltou_valor`); por isso o salvar recusa a condição `solicitante_de`
  # (ProblemasDoGatilho, `solicitante_sem_gravador`) e a tela não a oferece (useEscolhasDosGatilhos).
  GRAVADORES = [].freeze

  def self.gravado? = GRAVADORES.any?

  # O texto para o RH, só com os cards que `account_user` vê. Sem pessoa ou sem a condição (fora do recorrente com
  # `solicitante_de`, ou o ensaio, que não tem execução), vazio: o passo pula com `faltou_valor`.
  def self.texto_para(contato, account_user, condicao)
    return if account_user.nil? || condicao.blank?

    contexto = { user: account_user.user, account: contato.account, account_user: account_user }
    new(contato.account, condicao, visiveis: Pundit.policy_scope!(contexto, ::Crm::Card)).texto(contato).presence
  end

  def initialize(conta, condicao, visiveis: nil)
    @conta = conta
    @condicao = condicao.to_h
    @visiveis = visiveis
  end

  def faltando = Array(@condicao['faltando']).map(&:to_s).uniq

  def pendentes
    return ::Crm::Card.none if faltando.empty? || @condicao['funil_id'].blank?

    escopo = ::Crm::Card.where(account_id: @conta.id, pipeline_id: @condicao['funil_id'], status: ::Crm::Card.statuses[:open])
                        .where.not(solicitante_contact_id: nil)
    escopo = escopo.where(stage_id: @condicao['etapa_id']) if @condicao['etapa_id']
    escopo = escopo.where(id: @visiveis.select(:id)) if @visiveis
    escopo.where("(#{([SEM_MARCAR] * faltando.size).join(' OR ')})", *faltando)
  end

  # Os ids dos RHs a avisar, um por empresa: o solicitante do pendente mais novo dela.
  def representantes
    pendentes.joins(JUNTA).reorder(Arel.sql("#{EMPRESA}, crm_cards.id DESC"))
             .select(Arel.sql("DISTINCT ON (#{EMPRESA}) crm_cards.solicitante_contact_id"))
  end

  # Os pendentes da empresa do RH (ou só os dele, sem empresa), na ordem em que os cards nasceram.
  def do_rh(contato)
    solicitantes = contato.company_id ? ::Contact.where(account_id: @conta.id, company_id: contato.company_id).select(:id) : contato.id
    pendentes.where(solicitante_contact_id: solicitantes).includes(:contact).order(:id)
  end

  # "Ana Souza (CPF, comprovante); Carla Dias (RG, CPF, comprovante)". Nunca quebra de linha nem tab: a Meta recusa a
  # variável do modelo que tem.
  def texto(contato)
    rotulos = rotulos_dos_campos
    do_rh(contato).map { |card| "#{nome(card)} (#{faltam(card, rotulos).join(', ')})" }.join(SEPARADOR)
  end

  private

  def nome(card) = (card.contact&.name.presence || card.title).squish

  def faltam(card, rotulos)
    faltando.reject { |chave| card.custom_attributes.to_h[chave].to_s == 'true' }.map { |chave| rotulos.fetch(chave, chave).squish }
  end

  def rotulos_dos_campos
    @conta.custom_attribute_definitions.where(attribute_model: :card_attribute, attribute_key: faltando)
          .pluck(:attribute_key, :attribute_display_name).to_h
  end
end
