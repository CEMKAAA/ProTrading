const $ = (id) => document.getElementById(id);
let licenses = {};

function asCsv(value) {
  if (Array.isArray(value)) return value.join(",");
  return value || "";
}

function fmtStatus(rec) {
  return rec.active ? '<span class="pill on">ACTIVE</span>' : `<span class="pill off">${rec.reason || "INACTIVE"}</span>`;
}

function visibleRows() {
  const q = ($("search").value || "").toLowerCase();
  return Object.entries(licenses)
    .filter(([key, rec]) => {
      const hay = [key, rec.customer, asCsv(rec.product), asCsv(rec.account), rec.note, rec.reason].join(" ").toLowerCase();
      return hay.includes(q);
    })
    .sort((a, b) => String(b[1].updated_at || "").localeCompare(String(a[1].updated_at || "")));
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    ...options,
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.ok === false) throw new Error(body.error || body.reason || `HTTP ${res.status}`);
  return body;
}

function render() {
  const entries = visibleRows();
  $("licenseRows").innerHTML = entries.map(([key, rec]) => `
    <tr>
      <td>${fmtStatus(rec)}</td>
      <td><code>${key}</code></td>
      <td>${rec.customer || "-"}</td>
      <td>${asCsv(rec.product) || "*"}</td>
      <td>${asCsv(rec.account) || "*"}</td>
      <td>${rec.expires_at || "never"}</td>
      <td class="actions">
        <button onclick="editLicense('${key.replaceAll("'", "\\'")}')">Edit</button>
        ${rec.active
          ? `<button class="danger" onclick="deactivateLicense('${key.replaceAll("'", "\\'")}')">Deactivate</button>`
          : `<button class="success" onclick="activateLicense('${key.replaceAll("'", "\\'")}')">Activate</button>`}
        <button class="ghost danger-text" onclick="deleteLicense('${key.replaceAll("'", "\\'")}')">Delete</button>
      </td>
    </tr>
  `).join("");
  const all = Object.values(licenses);
  $("totalCount").textContent = all.length;
  $("activeCount").textContent = all.filter((x) => x.active).length;
  $("inactiveCount").textContent = all.filter((x) => !x.active).length;
}

async function loadLicenses() {
  const body = await api("/api/licenses");
  licenses = body.licenses || {};
  $("lastUpdate").textContent = body.updated_at ? body.updated_at.replace("T", " ").slice(0, 19) : "-";
  render();
}

async function loadAudit() {
  const body = await api("/api/audit?limit=150");
  const rows = body.rows || [];
  $("auditRows").innerHTML = rows.reverse().map((r) => `
    <div class="audit-row">
      <span>${(r.time_utc || "").replace("T", " ").slice(0, 19)}</span>
      <strong>${r.event || "-"}</strong>
      <code>${r.license_key || "-"}</code>
      <em>${r.detail || ""}</em>
    </div>
  `).join("");
}

function formPayload() {
  return {
    license_key: $("licenseKey").value.trim(),
    customer: $("customer").value.trim(),
    product: $("product").value.trim(),
    account: $("account").value.trim(),
    terminal: $("terminal").value.trim(),
    expires_at: $("expiresAt").value.trim(),
    note: $("note").value.trim(),
    active: $("active").checked,
  };
}

function clearForm() {
  ["licenseKey", "customer", "product", "account", "terminal", "expiresAt", "note"].forEach((id) => $(id).value = "");
  $("terminal").value = "MT5";
  $("active").checked = true;
}

window.editLicense = (key) => {
  const rec = licenses[key] || {};
  $("licenseKey").value = key;
  $("customer").value = rec.customer || "";
  $("product").value = asCsv(rec.product);
  $("account").value = asCsv(rec.account);
  $("terminal").value = asCsv(rec.terminal) || "MT5";
  $("expiresAt").value = rec.expires_at || "";
  $("note").value = rec.note || "";
  $("active").checked = !!rec.active;
  window.scrollTo({ top: 0, behavior: "smooth" });
};

async function saveLicense() {
  const payload = formPayload();
  if (!payload.license_key) return alert("License key required");
  await api("/api/licenses", { method: "POST", body: JSON.stringify(payload) });
  await loadLicenses();
  await loadAudit();
}

window.activateLicense = async (key) => {
  await api(`/api/licenses/${encodeURIComponent(key)}/activate`, { method: "POST" });
  await loadLicenses();
  await loadAudit();
};

window.deactivateLicense = async (key) => {
  const reason = prompt("Deactivate reason", "deactivated_by_admin") || "deactivated_by_admin";
  await api(`/api/licenses/${encodeURIComponent(key)}/deactivate`, {
    method: "POST",
    body: JSON.stringify({ reason }),
  });
  await loadLicenses();
  await loadAudit();
};

window.deleteLicense = async (key) => {
  if (!confirm(`Delete license ${key}? This cannot be undone.`)) return;
  await api(`/api/licenses/${encodeURIComponent(key)}`, { method: "DELETE" });
  await loadLicenses();
  await loadAudit();
};

$("saveBtn").addEventListener("click", saveLicense);
$("clearBtn").addEventListener("click", clearForm);
$("refreshBtn").addEventListener("click", async () => { await loadLicenses(); await loadAudit(); });
$("auditBtn").addEventListener("click", loadAudit);
$("search").addEventListener("input", render);

clearForm();
loadLicenses().catch((e) => alert(e.message));
loadAudit().catch(() => {});
