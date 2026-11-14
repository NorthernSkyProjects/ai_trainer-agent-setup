(() => {
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  const params = new URLSearchParams(window.location.search);
  const state = params.get("state") || "ready";
  const root = document.documentElement;
  const body = document.body;

  /* Theme ------------------------------------------------------------------ */
  const themeToggle = $("#theme-toggle");
  const stored = (() => { try { return localStorage.getItem("kachlog-theme"); } catch { return null; } })();
  const initialTheme = params.get("theme") || stored || root.dataset.theme || "light";

  applyTheme(initialTheme);
  themeToggle?.addEventListener("click", () => {
    applyTheme(root.dataset.theme === "dark" ? "light" : "dark");
    try { localStorage.setItem("kachlog-theme", root.dataset.theme); } catch {}
  });

  function applyTheme(theme) {
    root.dataset.theme = theme;
    root.classList.toggle("dark", theme === "dark");
    const dark = theme === "dark";
    const use = themeToggle?.querySelector("use");
    if (use) use.setAttribute("href", dark ? "#i-sun" : "#i-moon");
    themeToggle?.setAttribute("aria-label", dark ? "Светлая тема" : "Тёмная тема");
  }

  /* Sheet ------------------------------------------------------------------ */
  const backdrop = $("#sheet-backdrop");
  const sheet = $("#ai-sheet");
  const form = $("#ai-form");
  const pending = $("#ai-pending");
  const aiError = $("#ai-error");
  const submit = $("#ai-submit");
  const retryAi = $("#ai-retry");
  const textarea = sheet?.querySelector("textarea");
  const counter = sheet?.querySelector(".counter");
  let pendingTimer = null;
  let lastFocus = null;

  function openSheet() {
    if (!sheet || !backdrop) return;
    lastFocus = document.activeElement;
    backdrop.hidden = false;
    sheet.hidden = false;
    body.style.overflow = "hidden";
    setTimeout(() => textarea?.focus(), 40);
  }

  function closeSheet({ cancelled = false } = {}) {
    if (!sheet || !backdrop) return;
    clearTimeout(pendingTimer);
    pendingTimer = null;
    backdrop.hidden = true;
    sheet.hidden = true;
    body.style.overflow = "";
    setSheetState("form");
    if (cancelled) toast("Пересчёт отменён");
    if (lastFocus && typeof lastFocus.focus === "function") lastFocus.focus();
  }

  function setSheetState(next) {
    // next: "form" | "pending" | "error"
    if (!form || !pending || !aiError) return;
    form.hidden = next !== "form";
    pending.hidden = next !== "pending";
    aiError.hidden = next !== "error";
    const isPending = next === "pending";
    if (submit) {
      submit.disabled = isPending || (textarea?.value.trim().length ?? 0) === 0;
      submit.querySelector("span").textContent = isPending ? "Пересчитываем…" : "Отправить";
      submit.querySelector("use")?.setAttribute("href", isPending ? "#i-loader" : "#i-spark");
      submit.classList.toggle("is-loading", isPending);
    }
    if (next === "form") {
      updateCounter();
    }
  }

  function runAi() {
    setSheetState("pending");
    clearTimeout(pendingTimer);
    pendingTimer = setTimeout(() => {
      pendingTimer = null;
      closeSheet();
      toast("План обновлён");
    }, 2400);
  }

  function failAi() {
    clearTimeout(pendingTimer);
    pendingTimer = null;
    setSheetState("error");
  }

  $$("[data-open-ai]").forEach((btn) => btn.addEventListener("click", openSheet));
  $$("[data-close-sheet]").forEach((btn) => btn.addEventListener("click", () => closeSheet({ cancelled: !!pendingTimer })));
  backdrop?.addEventListener("click", () => closeSheet({ cancelled: !!pendingTimer }));
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && sheet && !sheet.hidden) {
      closeSheet({ cancelled: !!pendingTimer });
    }
    if (e.key === "Tab" && sheet && !sheet.hidden) trapFocus(e);
  });

  function trapFocus(e) {
    const focusable = $$("button, [href], input, textarea, summary, [tabindex]:not([tabindex='-1'])", sheet)
      .filter((el) => !el.disabled && el.offsetParent !== null);
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }

  /* Chips / counter --------------------------------------------------------- */
  function updateCounter() {
    if (!textarea || !counter) return;
    counter.textContent = `${textarea.value.length} / 1000`;
    if (submit && !pendingTimer) submit.disabled = textarea.value.trim().length === 0;
  }

  $$(".chip").forEach((chip) => {
    chip.addEventListener("click", () => {
      const active = chip.getAttribute("aria-pressed") === "true";
      chip.setAttribute("aria-pressed", String(!active));
      if (!textarea) return;
      const parts = textarea.value.split(/,\s*/).map((p) => p.trim()).filter(Boolean);
      const value = chip.textContent.trim();
      const next = parts.includes(value) ? parts.filter((p) => p !== value) : [...parts, value];
      textarea.value = next.join(", ");
      updateCounter();
    });
  });

  textarea?.addEventListener("input", updateCounter);
  updateCounter();

  submit?.addEventListener("click", () => {
    if (textarea?.value.trim().length === 0) return;
    runAi();
  });

  retryAi?.addEventListener("click", runAi);

  /* Day accordion ----------------------------------------------------------- */
  $$(".day-row.has-detail .icon-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const row = btn.closest(".day-row");
      const detail = row?.nextElementSibling;
      if (!detail?.classList.contains("day-detail")) return;
      const open = detail.hidden;
      detail.hidden = !open;
      row.classList.toggle("open", open);
      btn.setAttribute("aria-expanded", String(open));
      btn.setAttribute("aria-label", `${open ? "Свернуть" : "Раскрыть"} день`);
    });
  });

  /* Demo states ------------------------------------------------------------- */
  const ready = $("#ready");
  const loading = $("#loading");
  const error = $("#error");
  const empty = $("#empty");
  const partial = $("#partial-notice");
  const offline = params.get("offline") === "1" || params.get("offline") === "true";
  const map = { ready, loading, error, empty };

  Object.values(map).forEach((el) => { if (el) el.hidden = true; });
  if (partial) partial.hidden = true;

  const show = (name) => {
    Object.values(map).forEach((el) => { if (el) el.hidden = true; });
    const el = map[name];
    if (el) el.hidden = false;
  };

  body.dataset.state = state;

  if (offline) {
    const badge = $("#offline-badge");
    if (badge) badge.hidden = false;
  }

  if (state === "loading") {
    show("loading");
  } else if (state === "error") {
    show("error");
  } else if (state === "empty") {
    show("empty");
  } else {
    show("ready");
    if (state === "partial" && partial) partial.hidden = false;
    if (state === "ai" || state === "ai-pending" || state === "ai-error") {
      openSheet();
      if (state === "ai-pending") {
        if (params.get("freeze") === "1") setSheetState("pending");
        else runAi();
      }
      if (state === "ai-error") failAi();
    }
  }

  $("#toast"); // no-op, keeps the element in the DOM for accessibility

  /* Error retry ------------------------------------------------------------- */
  $$("[data-retry]").forEach((btn) => {
    btn.addEventListener("click", () => {
      show("ready");
      body.dataset.state = "ready";
      toast("План загружен");
    });
  });

  /* Toast ------------------------------------------------------------------- */
  let toastTimer;
  function toast(text) {
    const el = $("#toast");
    if (!el) return;
    el.textContent = text;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, 3200);
  }


  /* Validation hook: ?check=1 writes tap-target / overflow metrics into the DOM */
  if (params.get("check") === "1") {
    requestAnimationFrame(() => {
      const elements = $$("button, .chip, summary, a, label").filter((el) => el.offsetParent !== null);
      const small = elements
        .map((el) => ({ tag: el.className || el.tagName, h: Math.round(el.getBoundingClientRect().height) }))
        .filter((item) => item.h > 0 && item.h < 44);
      const pre = document.createElement("pre");
      pre.id = "tap-check";
      pre.textContent = JSON.stringify({
        width: window.innerWidth,
        scrollWidth: document.documentElement.scrollWidth,
        small,
        buttons: elements.length,
      });
      document.body.appendChild(pre);
    });
  }

  /* Expose a tiny demo API for screenshots / validation ---------------------- */
  window.KachlogDemo = { openSheet, closeSheet, setSheetState, runAi, failAi, toast, state };
})();
