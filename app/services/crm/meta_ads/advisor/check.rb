# A checagem do texto da IA (#1110, F5, CA-4.2, §1.5): nenhum número sai do modelo. Ele escreve com marcadores
# `{{fato}}` e o servidor põe os valores; aqui se confere que o texto respeitou isso antes de ele valer.
#
# O texto é saída de máquina num formato que nós definimos, não texto de pessoa sendo interpretado: a leitura é
# por posição de caractere (`String#index`, via Format.split_markers) e `each_char`, sem regex. O dígito é
# procurado depois de tirar os marcadores e normalizar com NFKC (dígito largo, "１", vira ASCII). Número por
# extenso ("três") não tem como ser pego sem lista de palavras: vale a autodeclaração `numbers_in_words` do modelo
# (risco 3 do desenho). Dígito não-ASCII que o NFKC não converte (árabe-índico) também não é pego; não aparece em
# pt/en/es.
#
# → { ok: [key], rejected: { key => [códigos] }, global: [códigos] }. Código global recusa todas as ações.
module Crm::MetaAds::Advisor::Check
  LIMITS = { 'headline' => 120, 'body' => 400, 'why' => 300 }.freeze

  module_function

  # actions: [{ key:, facts: { chave => valor } }], o que foi mandado ao modelo.
  def call(answer, actions)
    answer = {} unless answer.is_a?(Hash)
    global = answer['numbers_in_words'] == true ? ['numbers_in_words'] : []
    rejected = rejections(answered(answer), actions)
    ok = global.any? ? [] : actions.map { |action| action[:key].to_s } - rejected.keys
    { ok: ok, rejected: rejected, global: global }
  end

  def answered(answer)
    Array(answer['actions']).select { |entry| entry.is_a?(Hash) }.group_by { |entry| entry['key'].to_s }
  end

  # Cada ação enviada precisa voltar exatamente uma vez.
  def rejections(answered, actions)
    actions.each_with_object({}) do |action, all|
      found = answered[action[:key].to_s]
      codes = found&.size == 1 ? entry_codes(found.first, action[:facts].to_h.stringify_keys) : ['missing_action']
      all[action[:key].to_s] = codes if codes.any?
    end
  end

  def entry_codes(entry, facts)
    codes = LIMITS.flat_map { |field, limit| text_codes(field, entry[field].to_s, limit, facts) }
    codes << 'empty_headline' if entry['headline'].to_s.strip.empty?
    codes.uniq
  end

  # Tamanho medido no texto com marcadores: recusa, não corta (cortar pode partir um marcador).
  def text_codes(field, text, limit, facts)
    codes = text.length > limit ? ['too_long'] : []
    parts = Crm::MetaAds::Advisor::Format.split_markers(text)
    keys = parts&.filter_map(&:last)
    return codes << 'malformed_placeholder' if malformed?(keys)

    codes << 'digit_outside_fact' if digit?(parts.map(&:first).join)
    codes + marker_codes(field, keys, facts)
  end

  def malformed?(keys)
    keys.nil? || keys.any? { |key| key.empty? || key.include?('{') }
  end

  # Sem valor é o "fato inexistente" do CA-4.2: o mesmo vazio que faz o Format.render desistir.
  def marker_codes(field, keys, facts)
    codes = keys.any? { |key| facts[key].blank? } ? ['unknown_fact'] : []
    field == 'why' && keys.empty? ? codes << 'why_without_fact' : codes
  end

  def digit?(text)
    text.unicode_normalize(:nfkc).each_char.any? { |char| char.between?('0', '9') }
  end
end
