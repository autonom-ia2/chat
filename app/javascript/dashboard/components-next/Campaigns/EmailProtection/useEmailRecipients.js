// The per-person list of an e-mail campaign: search, situation and problem filters, pages,
// filtered export, copy e-mail and the refresh while someone is still waiting. Shared by the
// old Gestão table (EmailRecipients) and the Resultado list (#990), so both show the same rows.
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import ReportsAPI from 'dashboard/api/emailCampaignReports';
import { useEmailReportRefresh } from './useEmailReportRefresh';
import { NS, safeError, downloadCsv } from './presentation';

const SEARCH_DELAY_MS = 300;
const DEFAULT_PER_PAGE = 50;
const PROBLEMS = 'attention';

// source: { campaignId, refreshKey, problemOnly } as getters.
export function useEmailRecipients(source, { t }) {
  const { run, abort, isPending } = useAbortableRequest();
  const search = ref('');
  const status = ref(source.problemOnly() ? PROBLEMS : '');
  const problemStatus = ref(PROBLEMS);
  const page = ref(1);
  const recipients = ref([]);
  const meta = ref({});
  const errorMessage = ref('');
  const exportError = ref('');
  const exporting = ref(false);
  const copied = ref(null);
  let searchTimer;

  const isProblemFilter = computed(() => status.value === PROBLEMS);
  const filters = computed(() => {
    let selectedStatus = status.value;
    if (isProblemFilter.value) {
      selectedStatus =
        problemStatus.value === PROBLEMS ? '' : problemStatus.value;
    }
    return {
      search: search.value,
      status: selectedStatus,
      problem: isProblemFilter.value,
    };
  });

  const metricHelp = computed(() => {
    const hints = [t(`${NS}.METRICS_HINT`)];
    if (meta.value.delivery_mode && meta.value.delivery_mode !== 'ses') {
      hints.push(t(`${NS}.DELIVERY_HINT`));
    }
    return hints.join(' ');
  });

  const totalPages = computed(
    () =>
      meta.value.total_pages ??
      (Math.ceil(
        (meta.value.count || 0) / (meta.value.per_page || DEFAULT_PER_PAGE)
      ) ||
        1)
  );

  const recipientStatusRecord = recipient => ({
    ...recipient,
    delivery_mode:
      Object.hasOwn(recipient, 'delivery_mode') &&
      recipient.delivery_mode !== undefined
        ? recipient.delivery_mode
        : meta.value.delivery_mode,
  });

  const fetchRecipients = async () => {
    clearTimeout(searchTimer);
    errorMessage.value = '';
    try {
      const response = await run(signal =>
        ReportsAPI.getRecipients(source.campaignId(), {
          ...filters.value,
          page: page.value,
          signal,
        })
      );
      if (!response) return;
      recipients.value = response.data.payload.recipients || [];
      meta.value = response.data.payload.meta || {};
    } catch (error) {
      errorMessage.value = safeError(t, error);
    }
  };

  const resetPage = () => {
    page.value = 1;
  };

  watch(status, value => {
    if (value !== PROBLEMS) problemStatus.value = PROBLEMS;
    resetPage();
    fetchRecipients();
  });

  watch(problemStatus, () => {
    if (!isProblemFilter.value) return;
    resetPage();
    fetchRecipients();
  });

  watch(search, () => {
    abort();
    resetPage();
    clearTimeout(searchTimer);
    searchTimer = setTimeout(fetchRecipients, SEARCH_DELAY_MS);
  });

  watch(source.problemOnly, value => {
    if (value) {
      status.value = PROBLEMS;
      problemStatus.value = PROBLEMS;
    } else if (status.value === PROBLEMS) {
      status.value = '';
    }
  });

  watch(
    source.campaignId,
    () => {
      abort();
      resetPage();
      meta.value = {};
      recipients.value = [];
      fetchRecipients();
    },
    { immediate: true }
  );

  watch(source.refreshKey, fetchRecipients);

  const clearFilters = () => {
    search.value = '';
    status.value = '';
    problemStatus.value = PROBLEMS;
    resetPage();
    fetchRecipients();
  };

  const goToPage = value => {
    page.value = value;
    fetchRecipients();
  };

  const exportCsv = async () => {
    if (exporting.value) return;
    exporting.value = true;
    exportError.value = '';
    try {
      const { data } = await ReportsAPI.export(
        source.campaignId(),
        filters.value
      );
      downloadCsv(data, `email-campaign-${source.campaignId()}-filtered.csv`);
    } catch (error) {
      exportError.value = safeError(t, error);
    } finally {
      exporting.value = false;
    }
  };

  const copyEmail = async recipient => {
    try {
      await navigator.clipboard.writeText(recipient.email);
      copied.value = recipient.id;
    } catch (error) {
      exportError.value = t(`${NS}.ERROR`);
    }
  };

  useEmailReportRefresh(
    () => (!isPending.value ? fetchRecipients() : undefined),
    () =>
      recipients.value.some(
        row => row.status === 'pending' || row.preflight_status === 'unchecked'
      )
  );

  onBeforeUnmount(() => clearTimeout(searchTimer));

  const showProblems = () => {
    search.value = '';
    status.value = PROBLEMS;
    problemStatus.value = PROBLEMS;
    resetPage();
    fetchRecipients();
  };

  return {
    search,
    status,
    problemStatus,
    page,
    recipients,
    meta,
    errorMessage,
    exportError,
    exporting,
    copied,
    isPending,
    isProblemFilter,
    metricHelp,
    totalPages,
    recipientStatusRecord,
    fetchRecipients,
    clearFilters,
    goToPage,
    exportCsv,
    copyEmail,
    showProblems,
  };
}
