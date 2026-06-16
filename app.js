
// Service Areas functionality
async function loadServiceAreas() {
  if (state.serviceAreasLoading) return;
  state.serviceAreasLoading = true;
  state.serviceAreasError = null;
  renderServiceAreas();

  try {
    const response = await apiFetch("/api/v1/admin/service-areas");
    const data = await response.json();
    state.serviceAreas = data.data || [];
    state.serviceAreasError = null;
  } catch (error) {
    state.serviceAreasError = "������ �������� ��� ������������: " + error.message;
    state.serviceAreas = [];
  }

  state.serviceAreasLoading = false;
  renderServiceAreas();
}

function renderServiceAreas() {
  const tbody = document.getElementById("service-areas-tbody");
  if (!tbody) return;

  if (state.serviceAreasLoading) {
    tbody.innerHTML = `
      <tr>
        <td colspan="5">
          <div class="loading-state">
            <div class="spinner"></div>
            �������� ��� ������������...
          </div>
        </td>
      </tr>
    `;
    return;
  }

  if (state.serviceAreasError) {
    tbody.innerHTML = `
      <tr>
        <td colspan="5">
          <div class="error-state">
            <strong>������:</strong> ${escapeHtml(state.serviceAreasError)}
            <button class="link-button" type="button" onclick="loadServiceAreas()">���������</button>
          </div>
        </td>
      </tr>
    `;
    return;
  }

  if (state.serviceAreas.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="5">2
          <div class="empty-state">
            ��� ��� ������������
          </div>
        </td>
      </tr>
    `;
    return;
  }

  const searchTerm = document.getElementById("service-areas-search")?.value.toLowerCase() || "";
  const filteredAreas = state.serviceAreas.filter(area =>
    area.name.toLowerCase().includes(searchTerm)
  );

  tbody.innerHTML = filteredAreas.map(area => `
    <tr>
      <td><strong>${escapeHtml(area.name)}</strong></td>
      <td class="mono">${escapeHtml(area.slug || "�")}</td>
      <td>
        <span class="status-pill ${area.is_active ? 'success' : 'muted'}">
          ${area.is_active ? '�������' : '��������'}
        </span>
      </td>
      <td class="mono">
        ${area.min_lat.toFixed(6)}, ${area.min_lng.toFixed(6)}<br>
        ${area.max_lat.toFixed(6)}, ${area.max_lng.toFixed(6)}
      </td>
      <td class="table-actions">
        <button class="icon-button" type="button" onclick="alert('�������������� ���� ����������')" title="�������������">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
        </button>
      </td>
    </tr>
  `).join("");
}
