<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import { intlLocale } from '../metaAdsHelpers';
import { nomeDoEstado } from '../brasilEstados';
import { longDate } from '../dinheiroDoAnuncio';
import { siteNormalizado } from '../anuncioNovo';
import MetaAdsAdPreview from './MetaAdsAdPreview.vue';
import MetaAdsCreatePlacement from './MetaAdsCreatePlacement.vue';

// Anúncios da Meta (#2198), criar: o que vai para a Meta, numa tela. O quê (e para onde vai quem toca), onde aparece
// (Automático já marcado, com o Trocar ali mesmo), quem vê, o dinheiro por extenso e o nome. Nasce pausado: o aviso
// fica junto do botão. Post impulsionado (#2339): o post escolhido no lugar da mídia e do texto; o da Página roda só
// no Facebook, sem "Trocar".
const props = defineProps({
  pageName: { type: String, default: '' },
  phone: { type: String, default: '' },
  username: { type: String, default: '' },
  media: { type: Object, default: null },
  cards: { type: Array, default: () => [] },
  // O botão do anúncio (WHATSAPP, INSTAGRAM_DIRECT, MESSENGER, LEARN_MORE, SHOP_NOW) ou null.
  action: { type: String, default: null },
  perDayLine: { type: String, required: true },
  totalLine: { type: String, default: '' },
  dayLimitsLine: { type: String, default: '' },
  // Lugares que a chamada real já confirmou para este anúncio.
  placements: { type: Array, required: true },
  // Post impulsionado: o texto do post.
  postText: { type: String, default: '' },
});

const draft = defineModel({ type: Object, required: true });

const { t, locale } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.REVIEW';

const isPost = computed(() => draft.value.kind === 'post');
const facebookPost = computed(
  () => isPost.value && draft.value.post_source === 'facebook'
);

const what = computed(() => {
  if (isPost.value) {
    return t(`${KEY}.WHAT_POST.${draft.value.post_source.toUpperCase()}`, {
      username: props.username,
    });
  }
  return t(`${KEY}.WHAT_AD.${draft.value.destination}`, {
    number: props.phone,
    username: props.username,
    url: siteNormalizado(draft.value.site_url),
  });
});

const tap = computed(() => {
  if (facebookPost.value) return t(`${KEY}.TAP.POST_FACEBOOK`);
  if (isPost.value) {
    return t(
      `${KEY}.TAP.${props.action ? 'POST_INSTAGRAM_WHATSAPP' : 'POST_INSTAGRAM'}`
    );
  }
  return t(`${KEY}.TAP.${draft.value.destination}`);
});

const where = computed(() => {
  if (draft.value.region === 'BR') {
    return t('CRM_KANBAN.META_ADS_HUB.CRIAR.AUDIENCE.ALL_BRAZIL');
  }
  return new Intl.ListFormat(intlLocale(locale.value), {
    type: 'conjunction',
  }).format(draft.value.states.map(nomeDoEstado));
});

const ages = computed(() =>
  t(`${KEY}.AGES`, {
    min: draft.value.age_min,
    max: draft.value.age_max === 65 ? '65+' : draft.value.age_max,
  })
);

const dates = computed(() => {
  const start = longDate(draft.value.start_date, locale.value);
  return draft.value.end_date
    ? t(`${KEY}.DATES`, {
        start,
        end: longDate(draft.value.end_date, locale.value),
      })
    : t(`${KEY}.DATES_NO_END`, { start });
});
</script>

<template>
  <div
    data-create-review
    class="grid min-w-0 grid-cols-1 gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]"
  >
    <div class="flex min-w-0 flex-col gap-4">
      <dl class="m-0 grid gap-3">
        <div class="flex flex-col gap-1 rounded-xl bg-n-alpha-1 p-4">
          <dt class="text-xs font-semibold text-n-slate-11">
            {{ $t(`${KEY}.WHAT`) }}
          </dt>
          <dd
            data-create-review-what
            class="m-0 break-words text-sm text-n-slate-12"
          >
            {{ what }}
          </dd>
          <dd v-if="cards.length > 1" class="m-0 text-xs text-n-slate-11">
            {{ $t(`${KEY}.WHAT_CAROUSEL`, { count: cards.length }) }}
          </dd>
          <dd class="m-0 text-xs text-n-slate-11">{{ tap }}</dd>
        </div>
        <MetaAdsCreatePlacement
          :model-value="draft.placement"
          :fixed="facebookPost"
          :options="placements"
          @update:model-value="draft = { ...draft, placement: $event }"
        />
        <div class="flex flex-col gap-1 rounded-xl bg-n-alpha-1 p-4">
          <dt class="text-xs font-semibold text-n-slate-11">
            {{ $t(`${KEY}.WHO`) }}
          </dt>
          <dd data-create-review-who class="m-0 text-sm text-n-slate-12">
            {{ $t(`${KEY}.WHO_LINE`, { where, ages }) }}
          </dd>
          <dd v-if="draft.special_category" class="m-0 text-xs text-n-slate-11">
            {{ $t(`${KEY}.SPECIAL`) }}
          </dd>
        </div>
        <div class="flex flex-col gap-1 rounded-xl bg-n-alpha-1 p-4">
          <dt class="text-xs font-semibold text-n-slate-11">
            {{ $t(`${KEY}.MONEY`) }}
          </dt>
          <dd
            data-create-review-amount
            class="m-0 text-base font-semibold text-n-slate-12"
          >
            {{ perDayLine }}
          </dd>
          <dd class="m-0 text-sm text-n-slate-12">{{ totalLine }}</dd>
          <dd class="m-0 text-sm text-n-slate-11">{{ dayLimitsLine }}</dd>
          <dd class="m-0 text-sm text-n-slate-11">{{ dates }}</dd>
        </div>
      </dl>
      <Input
        :model-value="draft.name"
        data-create-name
        :label="$t(`${KEY}.NAME`)"
        :message="$t(`${KEY}.NAME_HINT`)"
        wrap-message
        @update:model-value="draft = { ...draft, name: $event }"
      />
      <p
        data-create-paused
        class="m-0 flex gap-2 rounded-xl bg-n-amber-2 p-3 text-sm text-n-amber-12"
      >
        <span
          class="i-lucide-circle-pause mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ $t(`${KEY}.PAUSED`) }}
      </p>
      <p class="m-0 flex gap-2 text-xs text-n-slate-10">
        <span
          class="i-lucide-shield-check mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        {{ $t(`${KEY}.AUDIT`) }}
      </p>
    </div>
    <MetaAdsAdPreview
      :page-name="pageName"
      :text="isPost ? postText : draft.text"
      :media="media"
      :cards="cards"
      :headline="draft.headline"
      :action="action"
      :places="facebookPost ? 'FACEBOOK' : draft.placement"
      :feed-only="facebookPost"
    />
  </div>
</template>
