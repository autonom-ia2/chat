# O modelo aprovado da Meta do passo "mensagem" (#2468, F4b). A receita guarda o nome, o idioma e um texto por variável
# do corpo ({{1}}, {{2}}...), com os mesmos valores do texto livre. O passo só usa o modelo quando a janela de 24 h do
# número oficial está fechada; nunca troca o texto livre por ele com a janela aberta, e o Híbrido pronto continua
# mandando texto (para ele a janela está aberta).
#
# O modelo é procurado na caixa da conversa, pelo nome e pelo idioma, na lista que a caixa sincroniza com a Meta (a
# mesma leitura do aviso do Agendamento, Crm::BookingV2::Notices::Route). Uma automação que roda em várias caixas
# serve a todas que têm o modelo. Não cria, não pede aprovação e não troca de modelo sozinha: o que não serve vira
# motivo no histórico.
class Autonomia::Automacao::ModeloWhatsapp
  # Só utilidade, por ora: propaganda custa mais e pede decisão do Rodrigo, a mesma regra do Followup
  # (Crm::FollowUps::EnvioForaDaJanela::CATEGORIA_PERMITIDA). Ligar MARKETING é pôr a categoria aqui e o aviso de custo
  # na tela.
  CATEGORIAS = %w[UTILITY].freeze
  # Só o número oficial (Cloud e 360dialog) tem modelo da Meta e janela de 24 h imposta por ela.
  CANAL = 'Channel::Whatsapp'.freeze
  ROTA = ::Crm::BookingV2::Notices::Route

  Pronto = Data.define(:template_params, :conteudo)

  def self.aplica?(conversa) = conversa.inbox&.channel_type == CANAL

  # O modelo da lista de uma caixa serve para um passo com `quantas` variáveis: aprovado, de categoria aceita, com o
  # corpo pedindo exatamente {{1}}..{{quantas}} e sem nada além do corpo para preencher (mídia ou variável no topo,
  # botão com link variável).
  def self.serve?(item, quantas)
    aprovado?(item) && categoria_aceita?(item) && encaixa?(item, quantas)
  end

  def self.aprovado?(item) = item.to_h['status'].to_s.casecmp?('approved')
  def self.categoria_aceita?(item) = CATEGORIAS.include?(item.to_h['category'].to_s.upcase)

  # Leitura por `split`, sem regex: o que vem entre `{{` e `}}` é o nome da variável.
  def self.encaixa?(item, quantas)
    nomes = ROTA.native_body(item).split('{{').drop(1).map { |parte| parte.split('}}').first.to_s.strip }.uniq
    nomes.sort == (1..quantas).map(&:to_s).sort && Array(item.to_h['components']).none? { |parte| ROTA.asks_more?(parte) }
  end

  # Alguma caixa WhatsApp oficial da conta tem o modelo pronto para este passo. A Receita confere ao salvar; na hora de
  # mandar, vale a caixa da conversa.
  def self.na_conta?(conta, modelo)
    quantas = Array(modelo['variaveis']).size
    conta.inboxes.where(channel_type: CANAL).includes(:channel).any? do |caixa|
      item = ROTA.synced_template(caixa, configurado(modelo))
      item && serve?(item, quantas)
    end
  end

  # A Receita confere ao salvar (o texto das variáveis ela lê como o do texto livre). Sem conta, como no catálogo, não
  # confere a caixa.
  def self.problemas_ao_salvar(conta, passo_id, modelo)
    return [] if modelo.nil? || conta.nil? || na_conta?(conta, modelo)

    [I18n.t('autonomia.automacao.receita.modelo_indisponivel', passo: passo_id, nome: modelo['nome'])]
  end

  def self.configurado(modelo) = { 'name' => modelo['nome'].to_s, 'language' => modelo['idioma'].to_s }

  def initialize(modelo, conversa, valores)
    @modelo = modelo
    @conversa = conversa
    @valores = valores
  end

  # Pronto para mandar, ou o motivo (texto) de não mandar.
  def preparar
    item = ROTA.synced_template(@conversa.inbox, self.class.configurado(@modelo))
    motivo = motivo_do_modelo(item)
    return motivo if motivo

    lidos = variaveis.map { |partes| ::Autonomia::Automacao::Texto.new(partes, @valores).montar }
    # Vazio, ou só quebra, tab e espaço: o que sobraria da limpeza abaixo é nada.
    return 'modelo_faltou_valor' if lidos.any? { |lido| lido.nil? || lido.split.empty? }

    # A Meta recusa variável de corpo com quebra de linha, tab ou espaços seguidos (erro 132018), e a recusa só chega
    # depois, com o passo já "ok": cada sequência de espaços vira um espaço, no envio e no texto do painel.
    pronto(item, lidos.map { |lido| lido.split.join(' ') })
  end

  private

  def motivo_do_modelo(item)
    return 'modelo_fora_da_caixa' if item.nil?
    return 'modelo_nao_aprovado' unless self.class.aprovado?(item)
    return 'modelo_de_propaganda' unless self.class.categoria_aceita?(item)

    'modelo_mudou' unless self.class.encaixa?(item, variaveis.size)
  end

  def variaveis = Array(@modelo['variaveis'])

  # O corpo no painel com os valores no lugar (troca de string, sem regex), como o aviso do Agendamento.
  def pronto(item, lidos)
    corpo = lidos.each_with_index.to_h { |lido, indice| [(indice + 1).to_s, lido] }
    conteudo = corpo.reduce(ROTA.native_body(item)) { |texto, (posicao, lido)| texto.gsub("{{#{posicao}}}") { lido } }
    Pronto.new(template_params: { name: item['name'], language: item['language'], processed_params: { body: corpo } },
               conteudo: conteudo)
  end
end
