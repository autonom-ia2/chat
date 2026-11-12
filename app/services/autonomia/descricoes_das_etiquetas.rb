# #2435: a descrição que a conta escreveu em cada etiqueta, para a IA aplicar e ler a etiqueta pelo critério escrito
# ("vip": "cliente com mais de 3 apólices"), e não só pelo nome. Só entram as etiquetas que têm descrição: a etiqueta
# sem descrição continua indo só pelo nome, como antes.
module Autonomia::DescricoesDasEtiquetas
  module_function

  # { 'vip' => 'cliente com mais de 3 apólices' } das etiquetas da conta com esses nomes.
  def de(account, titulos)
    return {} if account.nil? || titulos.blank?

    account.labels.where(title: titulos).where.not(description: [nil, '']).pluck(:title, :description)
           .to_h.transform_values(&:strip).compact_blank
  end
end
