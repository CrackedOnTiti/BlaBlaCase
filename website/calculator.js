// ── Config ──────────────────────────────────────────────────────────────────
// Replace with your Cloudflare Tunnel URL once the Pi is set up.
// During development you can point this at http://localhost:8000
const API_BASE = "https://api.blablacase.com";

// ── State ───────────────────────────────────────────────────────────────────
let allowances = null;
const counts = { adults: 1, minors: 0, children: 0 };

// ── Counter controls ────────────────────────────────────────────────────────
function adjust(group, delta) {
  counts[group] = Math.max(0, counts[group] + delta);
  if (group === "adults" && counts[group] < 1) counts[group] = 1; // at least 1 adult
  document.getElementById(`${group}-val`).textContent = counts[group];
  renderTable();
}

// ── Fetch allowances from the API ───────────────────────────────────────────
async function loadAllowances() {
  const loading = document.getElementById("calc-loading");
  const error   = document.getElementById("calc-error");
  const table   = document.getElementById("results-table");

  loading.style.display = "block";
  error.style.display   = "none";
  table.style.display   = "none";

  try {
    const res = await fetch(`${API_BASE}/allowances`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    allowances = data.items;

    const lastUpdated = document.getElementById("last-updated");
    if (data.last_updated) {
      const d = new Date(data.last_updated);
      const formatted = d.toLocaleDateString("fr-FR", { day: "2-digit", month: "2-digit", year: "numeric" });
      lastUpdated.textContent = `— À jour au ${formatted}`;
    }

    loading.style.display = "none";
    renderTable();
    table.style.display = "table";
  } catch (e) {
    console.error(e);
    loading.style.display = "none";
    error.style.display   = "block";
  }
}

// ── Render results table ─────────────────────────────────────────────────────
function renderTable() {
  if (!allowances) return;

  const tbody = document.getElementById("results-body");
  tbody.innerHTML = "";

  for (const item of allowances) {
    const adultQty  = item.per_adult  ?? 0;
    const minorQty  = item.per_minor  ?? adultQty;
    const childQty  = item.per_child  ?? 0;

    const total =
      adultQty  * counts.adults  +
      minorQty  * counts.minors  +
      childQty  * counts.children;

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${item.label}</td>
      <td>${formatQty(adultQty, item.unit)}</td>
      <td>${item.per_minor !== undefined ? formatQty(minorQty, item.unit) : "<em style='color:#555'>Interdit</em>"}</td>
      <td>${item.per_child !== undefined ? formatQty(childQty, item.unit) : "<em style='color:#555'>Interdit</em>"}</td>
      <td class="col-total">${formatQty(total, item.unit)}</td>
    `;
    tbody.appendChild(tr);
  }
}

function formatQty(qty, unit) {
  if (qty === 0) return "—";
  return `${qty} ${unit}`;
}

// ── Boot ─────────────────────────────────────────────────────────────────────
loadAllowances();
