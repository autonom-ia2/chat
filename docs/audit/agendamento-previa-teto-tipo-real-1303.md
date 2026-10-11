# Agendamento: teto no desenho da prévia, tipo real do arquivo e identidade conferida (#1303)

Data: 11/10/2026. Branch `fix/1303-previa-teto-tipo-real`, sobre `feat/1289-pagina-identidade` (PR #1302). Follow-up da
revisão de segurança do #1302 e condição para ligar `crm_booking_v2` em contas além do piloto. Sem migration.

## Decisões

- **Teto global de desenhos** (`Crm::BookingV2::PreviewImage::DrawLimit`). `N` vagas numeradas no Redis e uma chave por
  conta; pegar é `SET NX EX` (primeiro a da conta, depois a primeira vaga global livre; sem vaga global, a da conta
  volta na hora), soltar é `delete_if_equals` no `ensure` (só o dono solta). No máximo um desenho por conta: uma conta
  não ocupa todas as vagas. Padrão `N = 2`, ajuste por `CRM_BOOKING_PREVIEW_MAX_DRAWS` (inválido, zero ou negativo
  volta ao padrão; teto 16) — **mesmo valor no web e no Sidekiq**, porque cada processo lê o seu. Vaga expira em 120 s:
  acima da trava por página (30 s), do tempo-limite do web e de um desenho normal; um desenho que passe disso perde a
  vaga e pode furar o teto até terminar (preferível a vaga presa). Sem `KEYS` nem varredura. Servir a imagem guardada
  não passa pelo teto. Só falha do desenho marca a página como falha; erro do Redis ao pegar a vaga, não.
- **Cheio = neutra `no-store`**, o mesmo caminho de "desenho em andamento", com o motivo no log
  (`Booking preview image not drawn: draw_limit`) e a página posta na fila (no máximo um job a cada 5 min por página).
  A trava por página vem antes da vaga: pedidos repetidos da mesma página não gastam vaga. Teto cheio não deixa a
  marca de falha.
- **Pré-aquecimento em job** (`PreviewImage::Warmup`, fila `low`):
  - `PreviewImageWarmJob(profile_id)`: desenha a imagem da página e a de cada link por pessoa; idempotente; com o
    teto cheio, tenta de novo (`retry_on`, 5 vezes, 30 s) e desiste com registro.
  - Disparado depois das gravações bem-sucedidas que mudam a imagem (`after_action` no concern da marca, só em
    `update`, `publish`, `logo`, `photo`, `apply_identity` e `update_people`). Página fora do ar e gravação recusada
    não disparam. No máximo UM job esperando por página (`later_once`; a marca sai quando o job começa): quem tem login
    não enche a fila `low` repetindo gravações. Falha ao enfileirar é registrada e não vira erro da gravação.
  - `PreviewImageSweepJob`: quando `Content::RENDER_VERSION` sobe, o primeiro pedido que não acha a imagem guardada
    enfileira UMA varredura por versão (marca `SET NX` com a versão na chave, 30 dias). Lotes de 20, uma página por
    vez, continua de onde parou em outro job; página que acha o teto cheio vai para o job dela.
  - O pedido web ainda desenha (dentro do teto) quando chega antes do job: a versão da imagem depende também de nome
    e foto do perfil de quem atende e do idioma da conta, que não passam pelo painel da página, e responder a neutra
    no primeiro pedido deixaria a prévia errada na conversa de quem recebeu o link.
- **Tipo real do arquivo** (`Crm::BookingV2::ImageFile`, ponto único). Em ordem: até 2 MB; tipo guardado PNG, JPEG
  ou WebP; assinatura dos primeiros bytes igual a esse tipo (comparação de bytes); abre na libvips com até 16 MP e
  até 8000 px de lado (só o cabeçalho). Sem libvips: fora de produção vale a assinatura, com aviso no log; em
  produção o arquivo é recusado, com registro. O conteúdo só é lido
  do anexo que muda na gravação. A tela recebe `reason` (`image_size`, `image_type`, `image_content`, `image_pixels`)
  e mostra uma frase simples (en e pt_BR).
- **Anexo novo entra com uma linha**: `IMAGE_ATTACHMENTS = %i[logo photo]` em `Crm::BookingPageSettings`. Na união
  com `feat/1295-tema-logo`, a linha vira `%i[logo logo_dark photo]` (e o laço de `validate_images` daquela branch
  sai, porque a regra mora no `ImageFile`).
- **Identidade salva**: `save_from!` confere logo e foto da página (conteúdo lido do armazenamento) antes de copiar;
  não passou, 422 e nada é salvo. `assign_to`/`apply_to!` não põem na página a imagem salva que não passa, e aplicam o
  resto; a página nova nasce sem ela em vez de não nascer.
- **Docs**: `save_photo` cria `Crm::AgentAvailability` para quem atende (comentário no método e no modelo);
  `docs/liberacoes-por-conta.md` com o piloto Hub2You 1 e 16 + Autonom.ia 1 e a condição de liberação.

## Riscos aceitos

- Desenho que dure mais que 120 s fura o teto até terminar.
- Mudança que não passa pelo painel (nome/foto do perfil, idioma da conta, identidade salva mudando a foto de outras
  páginas) não dispara o job: a página é desenhada no primeiro pedido, dentro do teto.
- WebP animado é aceito (é WebP de verdade; a prévia usa o primeiro quadro).
- Em desenvolvimento sem libvips, só a assinatura é conferida.
- O arquivo aceito é servido como foi enviado (sem regravar): EXIF de foto de celular e bytes depois da imagem
  continuam no arquivo. Regravar no envio fica para issue própria (já era assim antes deste PR).
- Pré-existentes apontados na revisão e fora deste PR: o pedido web baixa a imagem guardada a cada pedido (fora do
  teto; o freio é o rack-attack por IP); o tempo-limite do Rack (`Rack::Timeout`, que não é `StandardError`) num
  desenho web lento responde 500 em vez da neutra; o avatar do perfil, usado na prévia, não passa pela conferência nova.

## Revisão

Dois revisores independentes (correção/concorrência e adversarial), 0 CRITICAL/HIGH. Corrigidos: fila `low` sem
dedupe no `after_action` e disparo em ações que não mudam a imagem; vaga por conta (uma conta não ocupa o teto
inteiro); erro do Redis marcando a página como falha; falha ao enfileirar virando 500; sem libvips em produção
aceitando só pela assinatura; teto de lado; testes com `sleep` longo e concorrência dependente de tempo.

## Validação

RSpec focado (prévia, teto, jobs, uploads, identidade, páginas, API pública v2, rack-attack do agendamento,
`formatos_spec`) com a libvips e sem ela; Vitest de `settings/booking`; RuboCop, ESLint e Prettier nos arquivos
tocados; `autonomia:guia:formatos:check`, `guide-map/check`, `check-fork-i18n` e `central-de-ajuda/conferir`. Números
no PR.
