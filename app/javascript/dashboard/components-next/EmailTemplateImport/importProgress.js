// The three sentences of "Estamos trazendo seu modelo" (#1099), from the step the job tells
// (progress.step: reading -> images -> checking -> done). Each line is done, now or waiting.
const ORDER = ['reading', 'images', 'checking'];
const LINES = ['READING', 'IMAGES', 'EDITABLE'];

export const progressLines = (progress = {}, status = 'queued') => {
  const step = status === 'ready' ? 'done' : progress.step || 'reading';
  const at = step === 'done' ? ORDER.length : Math.max(ORDER.indexOf(step), 0);
  return LINES.map((key, index) => {
    let state = 'wait';
    if (index < at) state = 'done';
    else if (index === at) state = 'now';
    const counted =
      key === 'IMAGES' && state === 'now' && progress.images_total > 0;
    return {
      key: counted ? 'IMAGES_COUNT' : key,
      state,
      params: counted
        ? { done: progress.images_done || 0, total: progress.images_total }
        : {},
    };
  });
};

// Bar from 10% to 100%: each step is a third, the images fill theirs as they come.
export const progressPercent = (progress = {}, status = 'queued') => {
  if (status === 'ready') return 100;
  const at = Math.max(ORDER.indexOf(progress.step || 'reading'), 0);
  let inside = 0.3;
  if (progress.step === 'images' && progress.images_total > 0) {
    inside = (progress.images_done || 0) / progress.images_total;
  }
  return Math.round(Math.min(95, Math.max(10, ((at + inside) / 3) * 100)));
};
