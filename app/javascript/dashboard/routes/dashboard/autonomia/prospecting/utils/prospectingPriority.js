// Só a prioridade (percentil da busca). O score é outra escala; cair nele
// mostraria no anel um número que a ordem da fila não usa.
export const priorityValue = lead => {
  const value = lead?.priority_score;
  if (value === null || value === undefined || value === '') return null;

  return Math.max(0, Math.min(100, Math.round(Number(value))));
};

export const priorityTheme = priority => {
  if (priority >= 75) {
    return {
      ring: '#10b981',
      ringBg: '#d1fae5',
      ringText: '#065f46',
      cardBg: 'bg-n-teal-2',
      title: 'Lead muito quente',
      titleClass: 'text-n-teal-11',
    };
  }

  if (priority >= 50) {
    return {
      ring: '#3b82f6',
      ringBg: '#dbeafe',
      ringText: '#1e40af',
      cardBg: 'bg-n-blue-2',
      title: 'Oportunidade alta',
      titleClass: 'text-n-blue-11',
    };
  }

  if (priority >= 25) {
    return {
      ring: '#f59e0b',
      ringBg: '#fef3c7',
      ringText: '#92400e',
      cardBg: 'bg-n-amber-2',
      title: 'Lead morno',
      titleClass: 'text-n-amber-11',
    };
  }

  return {
    ring: '#ef4444',
    ringBg: '#fee2e2',
    ringText: '#991b1b',
    cardBg: 'bg-n-ruby-2',
    title: 'Prioridade baixa',
    titleClass: 'text-n-ruby-11',
  };
};

const toneClass = tone => {
  const classes = {
    pain: {
      card: 'bg-n-ruby-2 border-n-ruby-5 text-n-ruby-11',
      iconClass: 'text-n-ruby-11',
    },
    opportunity: {
      card: 'bg-n-amber-2 border-n-amber-5 text-n-amber-11',
      iconClass: 'text-n-amber-11',
    },
    positive: {
      card: 'bg-n-teal-2 border-n-teal-5 text-n-teal-11',
      iconClass: 'text-n-teal-11',
    },
    neutral: {
      card: 'bg-n-slate-2 border-n-slate-5 text-n-slate-11',
      iconClass: 'text-n-slate-10',
    },
  };

  return classes[tone] || classes.neutral;
};

const googleRankTone = searchRank => {
  if (searchRank <= 3) return 'positive';
  if (searchRank <= 10) return 'neutral';

  return 'opportunity';
};

// Como no Orth: no modo GMN (e sem modo) nota alta é oportunidade, porque a
// ficha já é forte e sobra pouco a vender; no modo Geral é sinal positivo.
const ratingTone = (rating, scoreMode) => {
  if (rating >= 4.5) {
    return scoreMode === 'general' ? 'positive' : 'opportunity';
  }
  if (rating >= 4) return 'neutral';
  if (rating >= 3) return 'opportunity';

  return 'pain';
};

const reviewsTone = reviews => {
  if (reviews >= 100) return 'positive';
  if (reviews >= 20) return 'neutral';

  return 'opportunity';
};

const FEW_PHOTOS = 5;
const MANY_PHOTOS = 10;
const MAX_SIGNALS = 4;

const signal = (key, label, icon, tone, href = null) => ({
  key,
  label,
  icon,
  href,
  ...toneClass(tone),
});

const photosSignal = (photoCount, t) => {
  if (photoCount === 0) {
    return signal(
      'photos',
      t('PROSPECTING.SEARCH.CARD_SIGNALS.NO_PHOTO'),
      'i-lucide-image-off',
      'pain'
    );
  }
  if (photoCount < FEW_PHOTOS) {
    return signal(
      'photos',
      t('PROSPECTING.SEARCH.CARD_SIGNALS.FEW_PHOTOS'),
      'i-lucide-image',
      'opportunity'
    );
  }

  return signal(
    'photos',
    t('PROSPECTING.SEARCH.CARD_SIGNALS.PHOTOS', { count: photoCount }),
    'i-lucide-image',
    photoCount < MANY_PHOTOS ? 'neutral' : 'positive'
  );
};

const hasValue = value => value !== null && value !== undefined && value !== '';

// Sinais do card como no Orth (priority-utils.tsx deriveSignals): site, fone,
// fotos e posição no Google; a nota entra se couber e as avaliações (só no
// chat2you) se ainda sobrar vaga. Sem a contagem de fotos, o chip de fotos não
// aparece: "Sem foto" seria afirmar o que não sabemos.
export const leadPrioritySignals = (lead, { t, scoreMode } = {}) => {
  const website = lead?.website || null;
  const signals = [
    signal(
      'website',
      website
        ? t('PROSPECTING.SEARCH.CARD_SIGNALS.HAS_SITE')
        : t('PROSPECTING.SEARCH.CARD_SIGNALS.NO_SITE'),
      website ? 'i-lucide-globe' : 'i-lucide-globe-2',
      website ? 'positive' : 'pain',
      website
    ),
    signal(
      'phone',
      lead?.phone
        ? t('PROSPECTING.SEARCH.CARD_SIGNALS.HAS_PHONE')
        : t('PROSPECTING.SEARCH.CARD_SIGNALS.NO_PHONE'),
      lead?.phone ? 'i-lucide-phone' : 'i-lucide-phone-off',
      lead?.phone ? 'positive' : 'pain'
    ),
  ];

  if (hasValue(lead?.photo_count)) {
    signals.push(photosSignal(Number(lead.photo_count), t));
  }

  const searchRank = Number(lead?.search_rank || 0);
  if (searchRank > 0) {
    signals.push(
      signal(
        'rank',
        t('PROSPECTING.SEARCH.CARD_SIGNALS.GOOGLE_RANK', { rank: searchRank }),
        'i-lucide-map-pin',
        googleRankTone(searchRank)
      )
    );
  }

  const rating = Number(lead?.rating || 0);
  if (rating > 0 && signals.length < MAX_SIGNALS) {
    signals.push(
      signal(
        'rating',
        t('PROSPECTING.SEARCH.CARD_SIGNALS.RATING', {
          value: rating.toFixed(1),
        }),
        'i-lucide-star',
        ratingTone(rating, scoreMode)
      )
    );
  }

  const reviews = Number(lead?.reviews_count || 0);
  if (reviews > 0 && signals.length < MAX_SIGNALS) {
    signals.push(
      signal(
        'reviews',
        t('PROSPECTING.SEARCH.CARD_SIGNALS.REVIEWS', { count: reviews }),
        'i-lucide-message-square-text',
        reviewsTone(reviews)
      )
    );
  }

  return signals.slice(0, MAX_SIGNALS);
};
