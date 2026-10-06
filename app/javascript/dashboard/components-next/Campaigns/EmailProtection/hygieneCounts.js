// Address check of the people not sent yet: shared by the old Gestão (EmailHygieneSummary)
// and the Resultado (#990). Counts are mutually exclusive server classifications. Never infer
// zeros or subtract overlapping legacy import counters to manufacture readiness.
export const CLASSIFICATIONS = [
  'ready',
  'protected',
  'invalid',
  'review',
  'unknown',
  'unchecked',
  'duplicate',
];

const STATES = {
  processing: 'analysing',
  queued: 'analysing',
  analysing: 'analysing',
  completed: 'completed',
  ready: 'ready',
  blocked: 'protected',
  review: 'review',
};

export const hygieneState = preflight => STATES[preflight?.status] || 'unknown';

const suppliedClassifications = preflight =>
  CLASSIFICATIONS.filter(key => Object.hasOwn(preflight?.counts || {}, key));

export const isReconciled = preflight => {
  const counts = preflight?.counts;
  const supplied = suppliedClassifications(preflight);
  return Boolean(
    counts &&
      Number.isInteger(counts.total) &&
      counts.total >= 0 &&
      supplied.every(
        key => Number.isInteger(counts[key]) && counts[key] >= 0
      ) &&
      supplied.reduce((sum, key) => sum + counts[key], 0) === counts.total
  );
};

// Total first, then each classification with people in it; null while the counts do not add up.
export const visibleClassifications = preflight =>
  suppliedClassifications(preflight).filter(
    key => (preflight?.counts?.[key] || 0) > 0
  );

export const reconciledCounts = preflight => {
  if (!isReconciled(preflight)) return null;
  return ['total', ...visibleClassifications(preflight)].map(key => ({
    key,
    value: preflight.counts[key],
  }));
};
