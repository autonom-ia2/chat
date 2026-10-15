# Os modelos aprovados da caixa que o Jev pode julgar compatíveis com um tipo (#1587). Só entra o que o envio consegue
# mandar como está e preencher sozinho:
# - aprovado, UTILITY ou MARKETING, em pt_BR (o idioma dos modelos do tipo), num formato que o envio sabe mandar
#   (`SendableFormat`);
# - variável só no corpo (topo de texto fixo ou sem topo; botões sem variável) e cada variável ligada, no perfil
#   (`WhatsappTemplateProfile#fields`), a um campo do catálogo que o card preenche (cliente, empresa do cliente, negócio,
#   minha empresa, atendente). Coluna de planilha, horário e texto fixo ficam de fora: o follow-up não tem de onde tirar;
# - o que as regras de uso deixam (`Regras`). Do sistema, pesquisa de satisfação, agendamento, anúncios e cobrança têm fluxo
#   próprio, e o modelo de OUTRO tipo deste ponto (`c2y_*`, dono `fora_da_janela`) não serve: cada tipo tem o seu (um
#   "retomar contato" MARKETING nunca vira "andamento"). Modelo da conta entra em qualquer categoria.
# Ordem estável (nome, depois id da Meta): o pré-voo e o envio veem a mesma lista.
# Caixas irmãs na mesma WABA enxergam o mesmo modelo: vale o perfil da própria caixa e, entre os outros, o mais antigo.
class Whatsapp::Templates::EnvioForaDaJanela::Candidatos
  Candidato = Data.define(:nome, :idioma, :categoria, :texto, :campos, :sistema)

  GRUPOS = %w[cliente empresa_cliente negocio minha_empresa atendente].freeze
  # Hoje todo modelo do sistema tem fluxo próprio: a cobrança tem um pronto por momento e valor (o de outro momento diria
  # "vence hoje" num andamento), e o `c2y_*` é do seu tipo. Fica a regra geral para um dono novo que sirva a vários fins.
  DONOS_DE_OUTRO_FLUXO = (%w[satisfacao agendamento anuncios cobranca] + [Whatsapp::Templates::EnvioForaDaJanela::Tipos::DONO]).freeze
  APROVADO = 'APPROVED'.freeze
  CORPO = 'BODY'.freeze
  TOPO = 'HEADER'.freeze
  BOTOES = 'BUTTONS'.freeze
  TOPO_DE_TEXTO = 'TEXT'.freeze
  VARIAVEL = '{{'.freeze

  # excluir: nomes que quem chama já olhou (o modelo do próprio tipo).
  def initialize(inbox:, excluir: [])
    @inbox = inbox
    @excluir = excluir
  end

  def call
    lista.sort_by { |template| [template['name'].to_s, template['id'].to_s] }.filter_map { |template| candidato(template) }
  end

  private

  def lista
    Whatsapp::Templates::ChannelList.entries(@inbox.channel.class.where(id: @inbox.channel.id).pick(:message_templates))
  end

  def candidato(template)
    return unless aprovado?(template) && portugues?(template) && @excluir.exclude?(template['name']) && so_corpo_variavel?(template)

    perfil = perfis[WhatsappTemplateProfile.key_for(template['name'], template['language'])]
    campos = campos_ligados(corpo(template), perfil)
    return if campos.nil?

    usavel(template, perfil, campos)
  end

  def portugues?(template)
    template['language'].to_s.casecmp?(Whatsapp::Templates::Finalidades::IDIOMA)
  end

  def usavel(template, perfil, campos)
    sistema = Whatsapp::Templates::EnvioForaDaJanela::Regras.sistema?(template['name'], perfil)
    return if sistema && DONOS_DE_OUTRO_FLUXO.include?(dono(template['name'], perfil))

    categoria = template['category'].to_s.upcase
    return if Whatsapp::Templates::EnvioForaDaJanela::Regras.impedimento(account: @inbox.account, categoria: categoria, sistema: sistema)

    Candidato.new(nome: template['name'], idioma: template['language'], categoria: categoria, texto: corpo(template),
                  campos: campos, sistema: sistema)
  end

  def dono(nome, perfil)
    perfil&.system_owner.presence || Whatsapp::Templates::SystemTemplates.owner_for(nome)
  end

  def aprovado?(template)
    template['status'].to_s.upcase == APROVADO && Whatsapp::Templates::SendableFormat.sendable?(template)
  end

  def componentes(template)
    Whatsapp::Templates::SendableFormat.hashes(template['components'])
  end

  def corpo(template)
    componentes(template).find { |item| item['type'].to_s.casecmp?(CORPO) }&.dig('text').to_s
  end

  def so_corpo_variavel?(template)
    componentes(template).all? do |componente|
      case componente['type'].to_s.upcase
      when TOPO then componente['format'].to_s.upcase == TOPO_DE_TEXTO && componente['text'].to_s.exclude?(VARIAVEL)
      when BOTOES then botoes_fixos?(componente)
      else true
      end
    end
  end

  def botoes_fixos?(componente)
    Whatsapp::Templates::SendableFormat.hashes(componente['buttons']).none? { |botao| botao['url'].to_s.include?(VARIAVEL) }
  end

  # { posição => chave } de TODAS as variáveis do corpo, ou nil quando alguma não tem campo que o card preenche.
  def campos_ligados(texto, perfil)
    posicoes = Ai::Redacao::Chaves.extrair(texto).uniq
    return {} if posicoes.empty?

    ligados = perfil&.fields.to_h.slice(*posicoes)
    ligados if ligados.size == posicoes.size && ligados.values.all? { |chave| preenchivel?(chave) }
  end

  def preenchivel?(chave)
    TemplateFields::Catalog.known?(chave) && GRUPOS.include?(TemplateFields::Catalog.group(chave))
  end

  def perfis
    @perfis ||= WhatsappTemplateProfile.for_inbox(@inbox)
                                       .sort_by { |perfil| [perfil.inbox_id == @inbox.id ? 0 : 1, perfil.id] }
                                       .uniq(&:key).index_by(&:key)
  end
end
