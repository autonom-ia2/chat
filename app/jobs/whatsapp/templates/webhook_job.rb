# Avisos da Meta sobre modelos (#1337), separados do POST pelo `Whatsapp::Templates::WebhookEntry`. Fila default: a lista
# da caixa muda "na hora", sem esperar a fila low (sync, recibos e campanhas grandes).
class Whatsapp::Templates::WebhookJob < ApplicationJob
  queue_as :default

  # changes: [{ 'waba_id', 'time', 'field', 'value' }], na ordem do POST.
  def perform(changes)
    Array(changes).each do |change|
      Whatsapp::Templates::WebhookEvent.new(waba_id: change['waba_id'], time: change['time'], field: change['field'],
                                            value: change['value']).perform
    end
  end
end
