// Zip upload: get a presigned URL, PUT the file straight to S3, then create the scan.
document.getElementById('zip-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const file = document.getElementById('zip').files[0];
  const status = document.getElementById('zip-status');
  if (!file) { status.textContent = 'Choose a .zip file first.'; return; }
  try {
    status.textContent = 'Uploading…';
    const presign = await (await fetch('/api/uploads', { method: 'POST' })).json();
    const put = await fetch(presign.uploadUrl, { method: 'PUT', headers: { 'Content-Type': 'application/zip' }, body: file });
    if (!put.ok) throw new Error('Upload to storage failed (' + put.status + '). Check the bucket CORS settings.');
    status.textContent = 'Starting check…';
    const res = await fetch('/api/scans/zip', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ scanId: presign.scanId, teamId: window.TEAM_ID }) });
    const body = await res.json();
    if (!res.ok) throw new Error(body.error);
    window.location = body.redirect;
  } catch (err) {
    status.textContent = err.message;
  }
});
