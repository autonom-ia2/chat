# frozen_string_literal: true

# #1941 — "Falha ao enviar" só no que sai pelo webhook da caixa API (Webhooks::FalhaSoNoQueSai).
Rails.application.config.to_prepare do
  Webhooks::Trigger.prepend(Webhooks::FalhaSoNoQueSai) unless Webhooks::Trigger <= Webhooks::FalhaSoNoQueSai
end
