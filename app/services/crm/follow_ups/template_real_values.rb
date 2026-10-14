# Follow-up de IA com dados reais (#1336, épico #1320). Fora das 24 h a IA escolhe um modelo aprovado e preenchia TODAS
# as variáveis, inventando valor, data e responsável. Aqui, a variável que o perfil do modelo
# (`WhatsappTemplateProfile#fields`, ex. { "2" => "negocio.valor" }) liga a uma chave do catálogo (`TemplateFields`)
# sai do card, pelo `TemplateFields::Resolver.for_card`:
#
#   { body: 'Oi {{1}}, o valor de {{2}}…', variables: %w[1 2] }
#   => { body: 'Oi {{1}}, o valor de R$ 1.250,00…', variables: %w[1], filled: { '2' => 'R$ 1.250,00' } }
#
# A IA recebe o body já escrito e só as posições que sobram (o prompt não muda); `filled` não vai para ela e vence o
# que ela devolver no envio (os runners fazem o merge). Posição ligada a um rótulo da tela que não é chave do catálogo
# ("desconto", "data") fica com a IA, como antes.
#
# Card sem o dado que o modelo pede (decisão do Rodrigo, 14/10/2026: "outro modelo; sem nenhum, texto"): o modelo sai da
# lista, e a IA escolhe outro que não precise do dado; sem nenhum, o runner segue pelo Híbrido ou `no_template`, como
# já faz sem candidato. Essa regra mora só em #without_real_value.
#
# Só leitura, num job: o card é o do follow-up (acesso por funil é de quem lista, não daqui). Só modelos nativos; o
# modelo da caixa WhatsApp API ('api') não recebe variáveis.
class Crm::FollowUps::TemplateRealValues
  FLAG = 'followup_template_real_values'.freeze
  NATIVE = 'native'.freeze
  OPEN = '{{'.freeze
  CLOSE = '}}'.freeze

  def self.enabled?(card)
    card.present? && card.account.feature_enabled?(FLAG)
  end

  def initialize(card:, inbox:)
    @card = card
    @inbox = inbox
  end

  def apply(candidates)
    candidates.filter_map { |candidate| candidate[:kind] == NATIVE ? fill(candidate) : candidate }
  end

  private

  def fill(candidate)
    linked = linked_keys(candidate)
    return candidate if linked.empty?

    filled = linked.transform_values { |key| resolver.value(key) }
    return without_real_value(candidate) if filled.value?(nil)

    candidate.merge(body: written_body(candidate[:body], filled), variables: candidate[:variables] - filled.keys, filled: filled)
  end

  # Card sem o dado: o modelo não é oferecido (nunca inventar, nunca "R$ 0,00"). Trocar a regra é trocar só isto.
  def without_real_value(_candidate)
    nil
  end

  # { posição => chave do catálogo } das posições que o body usa. O texto fixo tem origem própria (a campanha).
  def linked_keys(candidate)
    fields = profiles[WhatsappTemplateProfile.key_for(candidate[:name], candidate[:language])]&.fields.to_h
    fields.select do |position, key|
      candidate[:variables].include?(position) && key != TemplateFields::Catalog::FIXED && TemplateFields::Catalog.known?(key)
    end
  end

  # Uma passada só pelo body: o valor escrito nunca é relido (um título com "{{2}}" fica como está).
  def written_body(body, filled)
    head, *rest = body.split(OPEN, -1)
    rest.reduce(head) do |text, part|
      position, tail = part.split(CLOSE, 2)
      tail && filled.key?(position.strip) ? "#{text}#{filled[position.strip]}#{tail}" : "#{text}#{OPEN}#{part}"
    end
  end

  # Caixas irmãs na mesma WABA enxergam o mesmo modelo; quando mais de um perfil serve, vale o da própria caixa e,
  # entre os outros, o mais antigo, para a escolha não depender da ordem do banco.
  def profiles
    @profiles ||= WhatsappTemplateProfile.for_inbox(@inbox)
                                         .sort_by { |profile| [profile.inbox_id == @inbox.id ? 0 : 1, profile.id] }
                                         .uniq(&:key).index_by(&:key)
  end

  def resolver
    @resolver ||= TemplateFields::Resolver.for_card(@card)
  end
end
