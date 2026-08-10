const sightingForm = document.getElementById('sightingForm');
const locationInput = document.getElementById('location');
const notesInput = document.getElementById('notes');
const sightingsList = document.getElementById('sightingsList');
const latestCard = document.getElementById('latest');
const STORAGE_KEY = 'rabbit-sightings';

function loadSightings() {
  const saved = localStorage.getItem(STORAGE_KEY);
  return saved ? JSON.parse(saved) : [];
}

function saveSightings(entries) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(entries));
}

function renderSightings() {
  const sightings = loadSightings();
  if (!sightings.length) {
    latestCard.textContent = 'No sightings yet.';
    sightingsList.innerHTML = '<li class="empty-state">Add a sighting to track your rabbit’s last known location.</li>';
    return;
  }

  const latest = sightings[0];
  latestCard.innerHTML = `
    <strong>${latest.location}</strong>
    <p>${latest.notes || 'No notes provided.'}</p>
    <time datetime="${latest.timestamp}">${new Date(latest.timestamp).toLocaleString()}</time>
  `;

  sightingsList.innerHTML = sightings.map(entry => `
    <li class="sighting-card">
      <strong>${entry.location}</strong>
      <p>${entry.notes || 'No additional notes.'}</p>
      <time datetime="${entry.timestamp}">${new Date(entry.timestamp).toLocaleString()}</time>
    </li>
  `).join('');
}

sightingForm.addEventListener('submit', event => {
  event.preventDefault();
  const location = locationInput.value.trim();
  const notes = notesInput.value.trim();
  if (!location) return;

  const sightings = loadSightings();
  const newSighting = {
    location,
    notes,
    timestamp: new Date().toISOString(),
  };

  saveSightings([newSighting, ...sightings]);
  locationInput.value = '';
  notesInput.value = '';
  renderSightings();
});

renderSightings();
